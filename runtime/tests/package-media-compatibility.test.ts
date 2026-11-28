import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';
import {join} from 'node:path';

const root = join(__dirname, '..', '..');
const swiftRoot = join(root, 'ios', 'Modula');

function swiftFiles(directory: string): string[] {
  return readdirSync(directory, {withFileTypes: true}).flatMap(entry => {
    const target = join(directory, entry.name);
    if (entry.isDirectory()) return swiftFiles(target);
    return entry.isFile() && entry.name.endsWith('.swift') ? [target] : [];
  });
}

const allNativeSource = swiftFiles(swiftRoot).map(file => readFileSync(file, 'utf8')).join('\n');
const compatibility = readFileSync(join(swiftRoot, 'ModuleRuntime', 'WebGamePackage.swift'), 'utf8');

test('signed package media dispatch remains centralized and covers every native surface', () => {
  for (const literal of [
    'application/vnd.modula.moliboo-asset-pack+json',
    'application/vnd.modula.game-web+tgz',
    'application/vnd.modula.web-runtime+tgz',
    'application/vnd.modula.asset-pack+tgz',
    'modula.sticker-pack.1',
  ]) {
    assert.equal(allNativeSource.split(literal).length - 1, 1, `${literal} must have one native authority`);
    assert.ok(compatibility.includes(literal), `${literal} missing from compatibility registry`);
  }

  for (const kind of [
    'molibooContent', 'stickerManifest', 'stickerAsset',
    'moduleContent', 'gubicGame', 'gubicRuntime',
  ]) assert.match(compatibility, new RegExp(`(?:case |, )${kind}(?:,|\\n)`));

  assert.match(compatibility, /static func dispatch\(schemaVersion: String, category: String, mediaType: String\)/);
  assert.match(compatibility, /schemaVersion == schemaVersion && \$0\.category == category && \$0\.mediaType == mediaType/);
});

test('package consumers use the reviewed dispatch instead of private media-type copies', () => {
  const productHub = readFileSync(join(swiftRoot, 'Features', 'ProductHub', 'ProductHubView.swift'), 'utf8');
  const moliboo = readFileSync(join(swiftRoot, 'Features', 'MolibooRegistry', 'MolibooPackages.swift'), 'utf8');
  const stickers = readFileSync(
    join(swiftRoot, 'DesignSystem', 'AdvancedInteraction', 'ModulaComposerMediaPanel.swift'),
    'utf8',
  );
  const client = readFileSync(join(swiftRoot, 'Core', 'Networking', 'GreenfieldClient.swift'), 'utf8');

  assert.match(productHub, /PackageMediaCompatibility\.dispatch/);
  assert.match(productHub, /PackageMediaCompatibility\.gubicInstalledArtifactMediaTypes/);
  assert.match(moliboo, /PackageMediaCompatibility\.dispatch/);
  assert.match(moliboo, /PackageMediaCompatibility\.moliboo\.mediaType/);
  assert.match(stickers, /PackageMediaCompatibility\.stickerSchemaVersion/);
  assert.match(stickers, /PackageMediaCompatibility\.stickerAsset\.mediaType/);
  assert.match(client, /PackageMediaCompatibility\.moliboo\.mediaType/);
});

test('security and rollback XCTest coverage remains wired for every package family', () => {
  const n4c = readFileSync(join(root, 'ios', 'ModulaTests', 'N4CTests.swift'), 'utf8');
  const moliboo = readFileSync(join(root, 'ios', 'ModulaTests', 'MOL03PackageTests.swift'), 'utf8');

  for (const testName of [
    'testEveryReviewedPackageShapeHasOneExactDispatch',
    'testUnknownTypesVersionsAndCategorySubstitutionFailClosed',
    'testContentOnlyModuleInstallRelaunchUpdateRollbackAndUninstall',
    'testPackagePlanRequiresSignedIOSModuleDescriptor',
    'testBothWebGameSlotsPreserveActiveAcrossRejectedUpdatesAndHealthRollback',
    'testCorruptActiveRegistryGameRestoresVerifiedPreviousRelease',
  ]) assert.ok(n4c.includes(testName), `${testName} regression was removed`);

  for (const testName of [
    'testInstallUpdateRollbackAndOfflineReload',
    'testRejectsForgedSignature',
    'testFailedActivationHealthCheckRestoresPreviousVersion',
  ]) assert.ok(moliboo.includes(testName), `${testName} regression was removed`);

  assert.match(allNativeSource, /ModuleReleaseTrust\.verify/);
  assert.match(allNativeSource, /PackageMediaCompatibility\.stickerAsset\.mediaType/);
});
