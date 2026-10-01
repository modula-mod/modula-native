import {blockModels, type BlockModel} from '../../ui/blocks';
import {createDocumentFromText, validateStructuredDocument} from './domain/document';
import type {VaultDocumentBlock, VaultStructuredDocument} from './domain/types';

/**
 * Block-level editing for structured notes. A rich note is edited as a list of
 * segments, one per block: text blocks get a text field, lists and checklists get
 * per-item editing, and everything the editor can't edit (dividers, links, file and
 * image references, blocks from a newer schema) is kept verbatim. Saving rebuilds the
 * document from the original blocks, so structure the editor doesn't understand is
 * never lost.
 */
export type TextRole = 'paragraph' | 'heading' | 'quote' | 'callout' | 'code';
export type Segment =
  | {id: string; kind: 'text'; role: TextRole; text: string; level?: 1 | 2 | 3}
  | {id: string; kind: 'list'; ordered: boolean; items: string[]}
  | {id: string; kind: 'checklist'; items: {text: string; checked: boolean}[]}
  | {id: string; kind: 'static'; model: BlockModel};

export type InsertKind = 'heading' | 'paragraph' | 'bullet-list' | 'checklist' | 'quote' | 'divider';

const TEXT_ROLES = new Set<string>(['paragraph', 'heading', 'quote', 'callout', 'code']);

function blockText(block: VaultDocumentBlock): string {
  if (Array.isArray(block.inlines) && block.inlines.length) return block.inlines.map(inline => inline?.text ?? '').join('');
  return typeof block.text === 'string' ? block.text : '';
}

/** Plain notes (only simple paragraphs) keep the single text field the UI tests use. */
export function isPlainDocument(document: unknown): boolean {
  const result = validateStructuredDocument(document);
  return result.valid && (document as VaultStructuredDocument).blocks.every(block =>
    block.type === 'paragraph' && Object.keys(block).every(key => ['id', 'type', 'text'].includes(key)));
}

export function segmentsFromDocument(document: unknown): Segment[] {
  const blocks = document && typeof document === 'object' ? (document as {blocks?: unknown}).blocks : undefined;
  if (!Array.isArray(blocks)) return [];
  const models = blockModels(document);
  return blocks.slice(0, models.length).map((raw, index): Segment => {
    const model = models[index]!;
    const block = (raw && typeof raw === 'object' ? raw : {}) as VaultDocumentBlock;
    const id = model.key;
    if (model.kind === 'unsupported' || typeof block.id !== 'string') return {id, kind: 'static', model};
    if (TEXT_ROLES.has(block.type)) {
      return {id, kind: 'text', role: block.type as TextRole, text: blockText(block),
        ...(block.type === 'heading' ? {level: model.kind === 'heading' ? model.level : 2} : {})};
    }
    if (model.kind === 'list') return {id, kind: 'list', ordered: model.ordered, items: model.items};
    if (model.kind === 'checklist') return {id, kind: 'checklist', items: model.items};
    return {id, kind: 'static', model};
  });
}

/** Turns the plain text field into segments, e.g. when the user inserts a heading. */
export function segmentsFromText(text: string): Segment[] {
  return createDocumentFromText(text).blocks.map(block => ({id: block.id, kind: 'text', role: 'paragraph', text: block.text ?? ''}));
}

export function newSegment(kind: InsertKind, existing: Segment[]): Segment {
  const used = new Set(existing.map(segment => segment.id));
  let n = existing.length + 1;
  while (used.has(`block-${n}`)) n++;
  const id = `block-${n}`;
  switch (kind) {
    case 'heading': return {id, kind: 'text', role: 'heading', level: 2, text: ''};
    case 'paragraph': return {id, kind: 'text', role: 'paragraph', text: ''};
    case 'quote': return {id, kind: 'text', role: 'quote', text: ''};
    case 'bullet-list': return {id, kind: 'list', ordered: false, items: ['']};
    case 'checklist': return {id, kind: 'checklist', items: [{text: '', checked: false}]};
    case 'divider': return {id, kind: 'static', model: {key: id, kind: 'divider'}};
  }
}

/**
 * Rebuilds a valid document. Edited blocks keep their id and every field the editor
 * doesn't own; inline marks are kept while the text is unchanged. Empty text blocks
 * and empty list items are dropped.
 */
export function documentFromSegments(segments: Segment[], original?: unknown): VaultStructuredDocument {
  const originals = new Map<string, VaultDocumentBlock>();
  const blocks = original && typeof original === 'object' ? (original as {blocks?: unknown}).blocks : undefined;
  if (Array.isArray(blocks)) {
    const models = blockModels(original);
    blocks.slice(0, models.length).forEach((raw, index) => {
      if (raw && typeof raw === 'object') originals.set(models[index]!.key, raw as VaultDocumentBlock);
    });
  }
  const pristine = new Map(segmentsFromDocument(original).map(segment => [segment.id, JSON.stringify(segment)]));
  const out: VaultDocumentBlock[] = [];
  for (const segment of segments) {
    const before = originals.get(segment.id);
    const id = before?.id ?? segment.id;
    // Untouched blocks are written back byte-for-byte.
    if (before && pristine.get(segment.id) === JSON.stringify(segment)) { out.push(before); continue; }
    switch (segment.kind) {
      case 'static': {
        if (before) out.push(before);
        else if (segment.model.kind === 'divider') out.push({id, type: 'divider'});
        break;
      }
      case 'text': {
        if (!segment.text.trim()) break;
        const unchanged = before && blockText(before) === segment.text;
        const {inlines, ...rest} = before ?? ({} as VaultDocumentBlock);
        const block: VaultDocumentBlock = {...rest, id, type: segment.role, text: segment.text};
        if (unchanged && inlines) block.inlines = inlines;
        if (segment.role === 'heading') block.level = segment.level ?? 2; else delete block.level;
        out.push(block);
        break;
      }
      case 'list': {
        const items = segment.items.map(item => item.trim()).filter(Boolean);
        if (!items.length) break;
        out.push({...(before ?? {}), id, type: segment.ordered ? 'numbered-list' : 'bullet-list', items});
        break;
      }
      case 'checklist': {
        const items = segment.items.filter(item => item.text.trim());
        if (!items.length) break;
        out.push({...(before ?? {}), id, type: 'checklist', items: items.map(item => item.text.trim()), checked: items.map(item => item.checked)});
        break;
      }
    }
  }
  return {schemaVersion: '1.0.0', blocks: out};
}

export function segmentsEqual(a: Segment[], b: Segment[]): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}
