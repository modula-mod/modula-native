/**
 * Turns a (possibly malformed, possibly newer-schema) structured document into a flat
 * list of render models. Never throws: anything it can't represent becomes an
 * `unsupported` model so the renderer shows a labelled placeholder instead of going
 * blank or crashing the module surface.
 */
export type BlockModel =
  | {key: string; kind: 'heading'; text: string; level: 1 | 2 | 3}
  | {key: string; kind: 'paragraph' | 'quote' | 'callout' | 'code'; text: string}
  | {key: string; kind: 'list'; ordered: boolean; items: string[]}
  | {key: string; kind: 'checklist'; items: {text: string; checked: boolean}[]}
  | {key: string; kind: 'divider'}
  | {key: string; kind: 'link'; title: string; url: string}
  | {key: string; kind: 'reference'; label: string; detail: string}
  | {key: string; kind: 'unsupported'; label: string};

export const MAX_RENDERED_BLOCKS = 500;
const MAX_TEXT = 20_000;

function str(value: unknown): string | undefined {
  return typeof value === 'string' ? value.slice(0, MAX_TEXT) : undefined;
}

function inlineText(value: unknown): string | undefined {
  if (!Array.isArray(value)) return undefined;
  const parts = value.map(item => (item && typeof item === 'object' ? str((item as {text?: unknown}).text) : undefined));
  return parts.some(part => part !== undefined) ? parts.filter(Boolean).join('') : undefined;
}

function safeLink(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  return /^(https?:|mailto:)/i.test(value) ? value : undefined;
}

export function blockModels(document: unknown): BlockModel[] {
  const blocks = document && typeof document === 'object' ? (document as {blocks?: unknown}).blocks : undefined;
  if (!Array.isArray(blocks)) return [];
  const seen = new Set<string>();
  const models = blocks.slice(0, MAX_RENDERED_BLOCKS).map((raw, index): BlockModel => {
    const block = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw as Record<string, unknown> : {};
    const candidate = typeof block.id === 'string' && block.id ? block.id : `index-${index}`;
    const key = seen.has(candidate) ? `${candidate}-${index}` : candidate;
    seen.add(key);
    const text = inlineText(block.inlines) ?? str(block.text) ?? '';
    const items = Array.isArray(block.items) ? block.items.filter((item): item is string => typeof item === 'string') : [];
    switch (block.type) {
      case 'heading': {
        const level = block.level === 1 || block.level === 3 ? block.level : 2;
        return text ? {key, kind: 'heading', text, level} : {key, kind: 'unsupported', label: 'Empty heading'};
      }
      case 'paragraph': case 'quote': case 'callout': case 'code':
        return {key, kind: block.type, text};
      case 'bullet-list': case 'numbered-list':
        return {key, kind: 'list', ordered: block.type === 'numbered-list', items};
      case 'checklist': {
        const checked = Array.isArray(block.checked) ? block.checked : [];
        return {key, kind: 'checklist', items: items.map((item, i) => ({text: item, checked: checked[i] === true}))};
      }
      case 'divider':
        return {key, kind: 'divider'};
      case 'link-preview': {
        const url = safeLink(block.url);
        return url ? {key, kind: 'link', title: str(block.title) ?? url, url} : {key, kind: 'unsupported', label: 'Link unavailable'};
      }
      case 'image-reference': case 'file-reference':
        return {key, kind: 'reference', label: block.type === 'image-reference' ? 'Image' : 'File',
          detail: str(block.title) ?? str(block.alt) ?? 'Attachment'};
      default:
        return {key, kind: 'unsupported', label: typeof block.type === 'string' ? `Unsupported block: ${block.type.slice(0, 40)}` : 'Unsupported content'};
    }
  });
  if (blocks.length > MAX_RENDERED_BLOCKS) {
    models.push({key: 'truncated', kind: 'unsupported', label: `${blocks.length - MAX_RENDERED_BLOCKS} more blocks not shown`});
  }
  return models;
}
