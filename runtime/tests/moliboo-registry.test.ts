import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';

// MOL-03A: the canonical Moliboo registry is validated on every CI run (the Swift validator runs in ModulaTests).
const root = join(__dirname, '..', '..');
type Character = {id: string; number: number; key: string; familyId: string; wearable: boolean; accessoryProfile: string | null;
  packageId: string; expressions: string[]; motionProfile: string; rendering: string; baseAsset: string;
  availability: 'released' | 'draft'; purchasable: boolean; conceptId?: string; thumbnail?: string;
  reactions: Record<string, {mood: string; line?: string}>};
type Registry = {schemaVersion: string; registryVersion: string; families: {id: string; range: [number, number]; wearable: boolean; motionProfile: string; series: number; availability: string}[];
  motionProfiles: Record<string, unknown>; characters: Character[]};
const registry = JSON.parse(readFileSync(join(root, 'ios/Modula/Resources/Moliboo/moliboo_registry.json'), 'utf8')) as Registry;
const expressions = ['neutral', 'happy', 'excited', 'curious', 'sleepy', 'surprised', 'sad'];

test('moliboo registry is generated from the native roster (not hand-edited)', () => {
  const out = execFileSync('python3', [join(root, 'Tools/moliboo/registry/generate_registry.py'), root, '--check'], {encoding: 'utf8'});
  assert.match(out, /up to date/);
});

test('moliboo registry accounts for every character with unique ids and resolvable references', () => {
  assert.equal(registry.schemaVersion, 'modula.moliboo.registry.1');
  const cs = registry.characters;
  assert.equal(registry.registryVersion, '1.1.0');
  assert.equal(cs.length, 215);
  assert.deepEqual(cs.map(c => c.number), Array.from({length: 215}, (_, i) => i + 1));
  assert.equal(new Set(cs.map(c => c.id)).size, cs.length);
  assert.equal(new Set(cs.map(c => c.key)).size, cs.length);
  assert.equal(new Set(cs.map(c => c.packageId)).size, cs.length);
  const families = new Map(registry.families.map(f => [f.id, f]));
  for (const c of cs) {
    const f = families.get(c.familyId);
    assert.ok(f, `${c.id} family`);
    assert.ok(c.number >= f.range[0] && c.number <= f.range[1], `${c.id} range`);
    assert.equal(c.id, `moliboo.${String(c.number).padStart(3, '0')}`);
    assert.equal(c.packageId, `moliboo.character.${String(c.number).padStart(3, '0')}`);
    assert.equal(c.rendering, '2d');
    assert.equal(c.purchasable, false);
    if (c.number <= 115) {
      assert.equal(c.availability, 'released');
      assert.equal(c.conceptId, undefined);
      assert.ok(c.baseAsset.startsWith('native2d:'), `${c.id} base asset`);
    } else {
      assert.equal(c.availability, 'draft');
      assert.equal(c.conceptId, `moliboo.concept.${c.number - 15}`);
      // Series 2 is drawn by the same native rig as #001–115; the package portrait is a thumbnail only.
      assert.equal(c.baseAsset, `native2d:spec/${c.key}`);
      assert.equal(c.thumbnail, `package:moliboo.character.${String(c.number).padStart(3, '0')}/portrait.png`);
      assert.equal(c.wearable, true);
      assert.equal(c.accessoryProfile, `fit/${c.key}`);
    }
    assert.equal(c.wearable, f.wearable, `${c.id} wearable`);
    assert.equal(c.accessoryProfile === null, !c.wearable, `${c.id} accessory profile`);
    assert.deepEqual([...c.expressions].sort(), [...expressions].sort(), `${c.id} expressions`);
    assert.ok(registry.motionProfiles[c.motionProfile], `${c.id} motion profile`);
    for (const r of ['tap', 'doubleTap', 'longPress', 'greeting', 'equip', 'signature']) assert.ok(c.reactions[r], `${c.id} ${r}`);
  }
  assert.equal(new Set(cs.map(c => c.reactions.signature.line)).size, cs.length);
  assert.equal(cs.filter(c => c.familyId === 'legends').length, 15);
  assert.ok(cs.filter(c => c.familyId === 'legends').every(c => !c.wearable));
  assert.equal(cs.filter(c => c.availability === 'draft').length, 100);
  assert.equal(cs.find(c => c.number === 101)?.key, 'kringle');
  assert.equal(cs.find(c => c.number === 116)?.key, 'brinlo');
  assert.equal(cs.find(c => c.number === 215)?.key, 'jubilo');
  const series2 = registry.families.filter(f => f.series === 2);
  assert.equal(series2.length, 10);
  assert.ok(series2.every(f => f.availability === 'draft' && f.wearable));
  assert.deepEqual(series2.map(f => f.range), [[116, 125], [126, 135], [136, 145], [146, 155], [156, 165], [166, 175], [176, 185], [186, 195], [196, 205], [206, 215]]);
});
