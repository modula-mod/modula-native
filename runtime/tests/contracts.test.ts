import test from 'node:test';
import assert from 'node:assert/strict';
import {compatibleVersion, satisfies, validateManifest, type ModuleManifest} from '../../packages/module-contracts/src/index';
import semverVectors from '../../packages/module-contracts/test-vectors/semver.json';
import hostRequestSchema from '../../packages/module-contracts/schemas/host-request.schema.json';
import contextSchema from '../../packages/module-contracts/schemas/module-context.schema.json';
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
test('semver ranges match the shared host vectors (Swift and Kotlin hosts run the same file)', () => {
  for (const item of semverVectors.satisfies) {
    assert.equal(satisfies(item.version, item.range), item.expected, `${item.range} vs ${item.version}`);
  }
});
test('patch and minor-compatible bumps stay openable; exact equality is gone', () => {
  assert.equal(satisfies('0.1.4', '0.1.0'), true);
  assert.equal(satisfies('0.1.0', '>=0.1.0 <0.3.0'), true);
});
test('host requests carry the surface token, never a session ID', () => {
  assert.deepEqual(hostRequestSchema.required, ['version', 'moduleID', 'surfaceToken', 'action', 'params']);
  assert.equal(hostRequestSchema.additionalProperties, false);
  assert.ok(!('sessionID' in hostRequestSchema.properties));
  assert.ok(contextSchema.required.includes('surfaceToken') && !('sessionID' in contextSchema.properties));
});
