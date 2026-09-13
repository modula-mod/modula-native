import type {ModuleManifest} from '@modula/module-contracts';
import {validateManifest} from '@modula/module-contracts';
import manifests from './manifests.json';
import {Diagnostic} from '../modules/Diagnostic';
import {VaultNotes} from '../modules/vault/VaultNotes';
const entries = {diagnostic: Diagnostic, vault: VaultNotes};
export const ModuleRegistry = new Map(manifests.map(value => {
  const manifest = value as ModuleManifest;
  validateManifest(manifest);
  const component = entries[manifest.entry as keyof typeof entries];
  if (!component) throw new Error('Module entry missing');
  return [manifest.id, {manifest, component}];
}));
