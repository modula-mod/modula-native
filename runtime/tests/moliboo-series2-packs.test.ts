import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';

const root = join(__dirname, '..', '..');

test('series 2 pack sources are complete, unsigned, and outside the app bundle', () => {
  const out = execFileSync('python3', [join(root, 'Tools/moliboo/packages/build_series2_sources.py'), root, '--check'], {encoding: 'utf8'});
  assert.match(out, /100 drafts, unsigned, not bundled/);
  const manifest = JSON.parse(readFileSync(join(root, 'Tools/moliboo/packages/series2/manifest.json'), 'utf8'));
  assert.equal(manifest.purchasable, false);
  assert.equal(manifest.signed, undefined);
  assert.equal(manifest.packages.length, 100);
  assert.equal(manifest.packages[0].number, 116);
  assert.equal(manifest.packages[0].key, 'brinlo');
  assert.equal(manifest.packages[99].number, 215);
  assert.ok(manifest.packages.every((p: {purchasable: boolean; signed: boolean; availability: string}) => p.purchasable === false && p.signed === false && p.availability === 'draft'));
});
