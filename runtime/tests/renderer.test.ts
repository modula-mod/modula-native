import test from 'node:test';
import assert from 'node:assert/strict';
import {moduleTheme} from '../src/ui/theme';
import {blockModels, MAX_RENDERED_BLOCKS} from '../src/ui/blocks';
import {normalizeNoteRows} from '../src/modules/vault/rows';

test('theme resolves tokens and survives missing or hostile environment values', () => {
  const fallback = moduleTheme(undefined);
  assert.equal(fallback.colors.accent, '#369CAA');
  assert.equal(fallback.minimumTouchTarget, 44);
  const hostile = moduleTheme({colorScheme: 'dark', oled: true, accent: 'javascript:alert(1)', textScale: Number.NaN, reduceMotion: true} as never);
  assert.equal(hostile.colors.accent, '#369CAA');
  assert.equal(hostile.colors.canvas, '#000000');
  assert.equal(hostile.textScale, 1);
  assert.equal(hostile.reduceMotion, true);
});

test('theme follows density, shape, contrast and Dynamic Type', () => {
  const compact = moduleTheme({colorScheme: 'light', oled: false, accent: '#FFD60A', density: 'compact', interfaceShape: 'precise',
    contrastPreference: 'higherContrast', reduceMotion: false, textScale: 2.4});
  assert.ok(compact.spacing.md < 16);
  assert.equal(compact.radius.card, 10);
  assert.equal(compact.colors.onAccent, '#0B1213', 'dark text on a light accent');
  assert.equal(compact.highContrast, true);
  assert.ok(compact.maxFontSizeMultiplier >= 2.4);
  assert.equal(moduleTheme({colorScheme: 'light', oled: false, accent: '#1B4F72', reduceMotion: false, textScale: 1}).colors.onAccent, '#FFFFFF');
});

test('block renderer maps every known block and falls back for unknown or malformed ones', () => {
  const models = blockModels({schemaVersion: '1.0.0', blocks: [
    {id: 'h', type: 'heading', text: 'Title', level: 9},
    {id: 'p', type: 'paragraph', inlines: [{text: 'Hello '}, {text: 'world', marks: [{type: 'bold'}]}]},
    {id: 'l', type: 'numbered-list', items: ['a', 3, 'b']},
    {id: 'c', type: 'checklist', items: ['x', 'y'], checked: [true]},
    {id: 'u', type: 'link-preview', url: 'javascript:alert(1)'},
    {id: 'k', type: 'link-preview', url: 'https://modula.digital', title: 'Modula'},
    {id: 'f', type: 'future-widget'},
    null, 'garbage',
    {id: 'h', type: 'divider'},
  ]});
  assert.deepEqual(models.map(m => m.kind), ['heading', 'paragraph', 'list', 'checklist', 'unsupported', 'link', 'unsupported', 'unsupported', 'unsupported', 'divider']);
  assert.equal(models[0].kind === 'heading' && models[0].level, 2);
  assert.equal(models[1].kind === 'paragraph' && models[1].text, 'Hello world');
  assert.deepEqual(models[2].kind === 'list' && models[2].items, ['a', 'b']);
  assert.deepEqual(models[3].kind === 'checklist' && models[3].items.map(i => i.checked), [true, false]);
  assert.equal(new Set(models.map(m => m.key)).size, models.length, 'keys stay unique with duplicate/missing ids');
  assert.deepEqual(blockModels(undefined), []);
  assert.deepEqual(blockModels({blocks: 'nope'}), []);
});

test('block renderer caps very large documents with a visible note', () => {
  const blocks = Array.from({length: MAX_RENDERED_BLOCKS + 7}, (_, i) => ({id: `b${i}`, type: 'paragraph', text: String(i)}));
  const models = blockModels({blocks});
  assert.equal(models.length, MAX_RENDERED_BLOCKS + 1);
  assert.equal(models.at(-1)?.kind, 'unsupported');
});

test('malformed note rows are repaired or dropped instead of crashing the list', () => {
  const rows = normalizeNoteRows([
    {record_id: 'ok', revision: 2, data: {title: 'Kept', plainTextProjection: 'Body', archived: false}},
    {record_id: 'no-data', revision: 1},
    {record_id: 'blank-title', data: {title: '   ', archived: 'yes'}},
    {data: {title: 'no id'}}, null, 42,
    {record_id: 'ok', data: {title: 'duplicate'}},
  ]);
  assert.deepEqual(rows.map(r => r.record_id), ['ok', 'no-data', 'blank-title']);
  assert.equal(rows[1].data.title, 'Untitled note');
  assert.equal(rows[1].data.plainTextProjection, '');
  assert.equal(rows[2].data.archived, false);
  assert.deepEqual(normalizeNoteRows('nope'), []);
  assert.deepEqual(normalizeNoteRows([{record_id: 'ok'}], rows).length, 0, 'pages never duplicate existing rows');
});
