import type {ModuleManifest} from '@modula/module-contracts';
import {validateManifest} from '@modula/module-contracts';
import manifests from './manifests.json';
import {Diagnostic} from '../modules/Diagnostic';
import {VaultNotes} from '../modules/vault/VaultNotes';
import {ConnectModule} from '../modules/connect/ConnectModule';
// `vault` is a TEMPORARY native fallback (see VAULT_NOTES_NATIVE_FALLBACK in VaultNotes.tsx).
// `connect` is a PREVIEW on mock data (spec v1.0); it never contacts a carrier or charges.
const entries = {diagnostic: Diagnostic, vault: VaultNotes, connect: ConnectModule};
export const ModuleRegistry = new Map(manifests.map(value => {
  const manifest = value as ModuleManifest;
  validateManifest(manifest);
  const component = entries[manifest.entry as keyof typeof entries];
  if (!component) throw new Error('Module entry missing');
  return [manifest.id, {manifest, component}];
}));
