export const BRIDGE_VERSION = '0.1.0';
export type ModuleManifest = {
  id: string; name: string; version: string; runtime: 'react-native'; entry: string;
  permissions: string[]; minHostVersion: string; minBridgeVersion: string;
  collections?: string[];
};
export type ModuleEnvironment = {
  colorScheme: 'light' | 'dark'; oled: boolean; accent: string;
  surfacePreference: 'native'; reduceMotion: boolean; textScale: number;
};
export type ModuleContext = {
  sessionID: string; moduleID: string; bridgeVersion: string;
  environment: ModuleEnvironment; userID: string | null;
};
export type HostEvent = {sessionID: string; name: string; environment?: ModuleEnvironment};
export function compatibleVersion(actual: string, minimum: string): boolean {
  const parse = (value: string) => /^\d+\.\d+\.\d+$/.test(value) ? value.split('.').map(Number) : null;
  const a = parse(actual), b = parse(minimum);
  if (!a || !b || a[0] !== b[0]) return false;
  return a[1]! > b[1]! || (a[1] === b[1] && a[2]! >= b[2]!);
}
export function validateManifest(manifest: ModuleManifest): void {
  if (!/^[a-z][a-z0-9.-]+$/.test(manifest.id) || manifest.runtime !== 'react-native'
      || !manifest.entry || !compatibleVersion('0.1.0', manifest.minHostVersion)
      || !compatibleVersion(BRIDGE_VERSION, manifest.minBridgeVersion)) throw new Error('Incompatible module manifest');
}

export type HostAction = 'navigation.open' | 'haptics.selection' | 'diagnostics.ready' | 'diagnostics.dataReady' | 'diagnostics.fail' | 'backend.records.list' | 'backend.records.get' | 'backend.records.create' | 'backend.records.update' | 'backend.records.delete';
