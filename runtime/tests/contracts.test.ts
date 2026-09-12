import test from 'node:test';
import assert from 'node:assert/strict';
import {compatibleVersion, validateManifest, type ModuleManifest} from '../../packages/module-contracts/src/index';
import manifests from '../src/registry/manifests.json';

test('bundled manifests have unique identities and compatible contracts', () => {
  assert.equal(new Set(manifests.map(m => m.id)).size, manifests.length);
  for (const manifest of manifests) validateManifest(manifest as ModuleManifest);
});
test('future bridge versions and prereleases are rejected', () => {
  assert.equal(compatibleVersion('0.1.0', '0.2.0'), false);
  assert.equal(compatibleVersion('0.1.0', '1.0.0'), false);
  assert.equal(compatibleVersion('0.1.0', '0.1.0-rc.0'), false);
  assert.throws(() => validateManifest({...manifests[0], runtime: 'expo'} as unknown as ModuleManifest));
});
