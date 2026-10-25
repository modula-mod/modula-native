#!/usr/bin/env node
// MOL-03E QA publisher for Moliboo asset packs (restricted QA only — never public).
// Builds the `modula.moliboo.assetpack.1` container from a character patch, signs the artifact SHA-256 with Ed25519
// exactly like `modula sign` (signature over the UTF-8 hex digest, keyId = sha256(SPKI DER)), and writes an immutable
// `modula.package.1` descriptor into <out>/catalog.json. The private key is read from MODULA_SIGNING_KEY_PATH and never printed.
//
// usage: publish_qa_package.mjs --patch character.json --version 2.0.0 --family dreamers --out <qa-root>
//        [--min-host 0.1.0] [--tamper-after-sign] [--thumb file.png]
import {createHash, createPrivateKey, createPublicKey, sign} from 'node:crypto'
import {existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, a, i, all) => {
  if (a.startsWith('--')) acc.push([a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true])
  return acc
}, []))
const need = k => { if (!args[k] || args[k] === true) { console.error(`missing --${k}`); process.exit(2) } return args[k] }
const sha256 = b => createHash('sha256').update(b).digest('hex')

const patchBytes = readFileSync(need('patch'))
const patch = JSON.parse(patchBytes)
const version = need('version')
const out = need('out')
const family = need('family')
if (!/^\d+\.\d+\.\d+$/.test(version)) { console.error('version must be SemVer'); process.exit(2) }
if (patch.assetVersion !== version) { console.error('patch.assetVersion must equal --version'); process.exit(2) }
const number = patch.characterId.split('.')[1]
const packageId = `moliboo.character.${number}`

const files = [{path: 'character.json', mediaType: 'application/json', sha256: sha256(patchBytes), bytes: patchBytes.length, data: patchBytes.toString('base64')}]
if (args.thumb && args.thumb !== true) {
  const t = readFileSync(args.thumb)
  files.push({path: `thumbs/${patch.key}-128.png`, mediaType: 'image/png', sha256: sha256(t), bytes: t.length, data: t.toString('base64')})
}
const container = {schemaVersion: 'modula.moliboo.assetpack.1', packageId, version, characterId: patch.characterId, files}
let artifact = Buffer.from(JSON.stringify(container))
const digest = sha256(artifact)

const keyPath = process.env.MODULA_SIGNING_KEY_PATH
if (!keyPath) { console.error('MODULA_SIGNING_KEY_PATH is not set (the key is never printed).'); process.exit(1) }
const key = createPrivateKey(readFileSync(keyPath))
if (key.asymmetricKeyType !== 'ed25519') { console.error('Signing key must be Ed25519.'); process.exit(1) }
const keyId = sha256(createPublicKey(key).export({type: 'spki', format: 'der'}))
const signature = sign(null, Buffer.from(digest, 'utf8'), key).toString('base64')

if (args['tamper-after-sign']) {
  // Negative OTA case: bytes change after signing, so the published digest/signature no longer match.
  const evil = JSON.parse(artifact)
  evil.files[0].data = Buffer.from(JSON.stringify({...patch, form: 'tampered'})).toString('base64')
  artifact = Buffer.from(JSON.stringify(evil))
}

const rel = `artifacts/${packageId}-${version}.json`
mkdirSync(join(out, 'artifacts'), {recursive: true})
const dest = join(out, rel)
if (existsSync(dest) && sha256(readFileSync(dest)) !== sha256(artifact)) {
  console.error(`${packageId}@${version} already published with different bytes (versions are immutable)`); process.exit(1)
}
writeFileSync(dest, artifact)

const descriptor = {
  schemaVersion: 'modula.package.1', packageId, publisherId: 'modula', category: 'asset-pack', version,
  releaseId: `qa-${packageId}-${version}`,
  artifact: {sha256: digest, compressedSizeBytes: artifact.length, installedSizeEstimateBytes: files.reduce((n, f) => n + f.bytes, 0),
    mediaType: 'application/vnd.modula.moliboo-asset-pack+json', download: {pathOrUrl: rel, authorization: 'none', range: false}},
  signature: {algorithm: 'Ed25519', keyId, signature, statementDigest: null},
  minimumHostVersion: args['min-host'] && args['min-host'] !== true ? args['min-host'] : '0.1.0',
  platforms: ['ios'], dependencies: [], requiredCapabilities: [], cachePolicy: 'retain-while-owned', sharing: 'public-immutable',
  moliboo: {characterId: patch.characterId, familyId: family, runtimeVersion: 1, assetCapabilities: Object.keys(patch).filter(k => !['schemaVersion', 'characterId', 'key', 'assetVersion'].includes(k)), rollbackCompatible: true},
}
const catPath = join(out, 'catalog.json')
const catalog = existsSync(catPath) ? JSON.parse(readFileSync(catPath)) : {schemaVersion: 'modula.moliboo.catalog.1', packages: []}
catalog.packages = catalog.packages.filter(p => !(p.packageId === packageId && p.version === version)).concat([descriptor])
  .sort((a, b) => a.packageId.localeCompare(b.packageId) || a.version.localeCompare(b.version, undefined, {numeric: true}))
writeFileSync(catPath, JSON.stringify(catalog, null, 2) + '\n')
console.log(`published ${packageId}@${version} digest=${digest.slice(0, 12)}… key=${keyId.slice(0, 12)}…${args['tamper-after-sign'] ? ' (TAMPERED after signing)' : ''}`)
