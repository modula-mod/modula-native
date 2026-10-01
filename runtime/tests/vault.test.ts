import test from 'node:test';
import assert from 'node:assert/strict';
import {documentFromSegments, isPlainDocument, newSegment, segmentsFromDocument, segmentsFromText} from '../src/modules/vault/editing';
import {orderForDisplay, relativeTime, saveData, saveDocumentData, type NoteRow} from '../src/modules/vault/model';
import {validateStructuredDocument} from '../src/modules/vault/domain/document';
import {normalizeNoteRows} from '../src/modules/vault/rows';

const rich = {schemaVersion: '1.0.0' as const, blocks: [
  {id: 'h', type: 'heading' as const, level: 1 as const, text: 'Plan'},
  {id: 'p', type: 'paragraph' as const, inlines: [{text: 'Bold ', marks: [{type: 'bold' as const}]}, {text: 'start'}]},
  {id: 'd', type: 'divider' as const},
  {id: 'c', type: 'checklist' as const, items: ['Ship', 'Test'], checked: [true, false]},
  {id: 'l', type: 'link-preview' as const, url: 'https://modula.digital', title: 'Modula'},
  {id: 'f', type: 'file-reference' as const, sourceRef: 'file:1', title: 'Spec.pdf'},
]};

test('rich notes edit block by block and keep structure the editor does not own', () => {
  assert.equal(isPlainDocument(rich), false);
  const segments = segmentsFromDocument(rich);
  assert.deepEqual(segments.map(s => s.kind), ['text', 'text', 'static', 'checklist', 'static', 'static']);
  // Untouched round trip is lossless (inline marks, references, link).
  assert.deepEqual(documentFromSegments(segments, rich), rich);
  // Edit the heading and tick an item: ids, level and other blocks survive.
  const edited = segments.map(s => s.id === 'h' && s.kind === 'text' ? {...s, text: 'Plan v2'}
    : s.kind === 'checklist' ? {...s, items: s.items.map(i => ({...i, checked: true}))} : s);
  const doc = documentFromSegments(edited, rich);
  assert.equal(validateStructuredDocument(doc).valid, true);
  assert.deepEqual(doc.blocks[0], {id: 'h', type: 'heading', level: 1, text: 'Plan v2'});
  assert.deepEqual(doc.blocks[1], rich.blocks[1], 'inline marks kept while text unchanged');
  assert.deepEqual((doc.blocks[3] as {checked?: boolean[]}).checked, [true, true]);
  assert.deepEqual(doc.blocks.slice(4), rich.blocks.slice(4));
  // Changing marked text drops the marks for that block only, never the text.
  const plainP = documentFromSegments(segments.map(s => s.id === 'p' && s.kind === 'text' ? {...s, text: 'Plain now'} : s), rich);
  assert.deepEqual(plainP.blocks[1], {id: 'p', type: 'paragraph', text: 'Plain now'});
});

test('inserting blocks turns a plain note into a valid structured note', () => {
  const base = segmentsFromText('First\n\nSecond');
  const withBlocks = [...base];
  for (const kind of ['heading', 'checklist', 'divider'] as const) withBlocks.push(newSegment(kind, withBlocks));
  const filled = withBlocks.map(s => s.kind === 'text' && s.role === 'heading' ? {...s, text: 'Title'}
    : s.kind === 'checklist' ? {...s, items: [{text: 'Do it', checked: false}, {text: '  ', checked: true}]} : s);
  const doc = documentFromSegments(filled);
  assert.equal(validateStructuredDocument(doc).valid, true, JSON.stringify(validateStructuredDocument(doc).issues));
  assert.deepEqual(doc.blocks.map(b => b.type), ['paragraph', 'paragraph', 'heading', 'checklist', 'divider']);
  assert.deepEqual((doc.blocks[3] as {items?: string[]}).items, ['Do it'], 'blank items are dropped');
  assert.equal(new Set(doc.blocks.map(b => b.id)).size, doc.blocks.length, 'ids stay unique');
  const data = saveDocumentData(' Shopping ', doc, undefined, {pinned: true});
  assert.equal(data.title, 'Shopping');
  assert.equal(data.pinned, true);
  assert.match(data.plainTextProjection, /Do it/);
});

test('save validation explains what is wrong', () => {
  assert.throws(() => saveData('', 'text'), /title/);
  assert.throws(() => saveData('Title', '   '), /content/);
  assert.throws(() => saveDocumentData('T', {schemaVersion: '1.0.0', blocks: []}), /content/);
  assert.throws(() => saveDocumentData('T', {schemaVersion: '1.0.0', blocks: [{id: 'x', type: 'kanban' as never}]}), /newer Vault version/);
  assert.equal(saveData('T', 'Body', undefined, {pinned: true}).pinned, true);
});

test('list helpers: pinned first, timestamps, hostile rows', () => {
  const rows = normalizeNoteRows([
    {record_id: 'a', revision: 1, data: {title: 'A'}, updated_at: '2026-10-01T10:00:00.000Z'},
    {record_id: 'b', revision: 1, data: {title: 'B', pinned: true}},
    {record_id: 'c', revision: 1, data: {title: 'C'}, updated_at: {evil: true}},
  ]) as NoteRow[];
  assert.deepEqual(orderForDisplay(rows).map(r => r.record_id), ['b', 'a', 'c']);
  assert.equal(rows[0]!.updated_at, '2026-10-01T10:00:00.000Z');
  assert.equal(rows[2]!.updated_at, undefined);
  const now = Date.parse('2026-10-01T12:00:00.000Z');
  assert.equal(relativeTime('2026-10-01T11:59:30.000Z', now), 'Just now');
  assert.equal(relativeTime('2026-10-01T11:15:00.000Z', now), '45 min ago');
  assert.equal(relativeTime('2026-10-01T09:00:00.000Z', now), '3 h ago');
  assert.equal(relativeTime('2026-09-30T08:00:00.000Z', now), 'Yesterday');
  assert.equal(relativeTime('2026-09-12T08:00:00.000Z', now), '12 Sep');
  assert.equal(relativeTime('2025-09-12T08:00:00.000Z', now), '12 Sep 2025');
  assert.equal(relativeTime('nope', now), undefined);
});
