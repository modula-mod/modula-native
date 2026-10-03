/**
 * Host ⇄ module contract shared by the iOS host and the future Kotlin host.
 * JSON Schemas for every wire shape live in `../schemas`; shared test vectors live in
 * `../test-vectors`. Keep the three in sync (see docs/architecture/host-bridge.md).
 */
export const BRIDGE_VERSION = '0.1.0';
/** The host contract version modules compare `minHostVersion` against. */
export const HOST_VERSION = '0.1.0';

export type ModuleManifest = {
  id: string; name: string; version: string; runtime: 'react-native'; entry: string;
  permissions: string[];
  /** Semver range of host contract versions the module runs on (bare version = caret). */
  minHostVersion: string;
  /** Semver range of bridge versions the module runs on (bare version = caret). */
  minBridgeVersion: string;
  collections?: string[];
};
export type ModuleEnvironment = {
  designContractVersion?: 1;
  colorScheme: 'light' | 'dark'; theme?: 'system' | 'light' | 'dark';
  darkStyle?: 'standard' | 'dim' | 'oled'; oled: boolean; accent: string;
  fontFamily?: 'system' | 'rounded' | 'humanist' | 'geometric' | 'editorial' | 'mono';
  density?: 'compact' | 'standard' | 'comfortable';
  motionPersonality?: 'calm' | 'standard' | 'expressive';
  hapticIntensity?: 'off' | 'light' | 'standard' | 'strong';
  contrastPreference?: 'standard' | 'higherContrast';
  transparencyPreference?: 'standard' | 'reduceTransparency';
  iconStyle?: 'outline' | 'balanced' | 'filled';
  interfaceShape?: 'soft' | 'balanced' | 'precise';
  moduleBranding?: 'moduleIdentity' | 'blend' | 'preferUserAccent';
  reduceMotion: boolean; textScale: number;
};
export type LifecycleName = 'mounted' | 'active' | 'inactive' | 'backgrounded' | 'foregrounded' | 'unmounted'
  | 'memoryPressure' | 'appearanceChanged' | 'suspended' | 'resumed';
/**
 * Root props of one module surface (schemas/module-context.schema.json). They are set
 * natively on that surface only; updates arrive as new props on the same surface, never
 * as a broadcast to the shared JS context.
 */
export type ModuleContext = {
  /** Opaque, native-issued capability bound to this surface. Never the native session ID. */
  surfaceToken: string;
  moduleID: string; bridgeVersion: string;
  environment: ModuleEnvironment;
  /** Present only when the module declares and is granted `identity.userID`. */
  userID: string | null;
  /** Whether a shell account is signed in (non-identifying). */
  signedIn: boolean;
  initialPath?: string | null;
  /** Latest lifecycle event for this surface, with a monotonically increasing sequence. */
  lifecycle?: LifecycleName; eventSequence?: number;
};
export type HostEvent = {name: LifecycleName | string; sequence: number; environment?: ModuleEnvironment};

/** schemas/host-request.schema.json */
export type HostRequest = {version: string; moduleID: string; surfaceToken: string; action: HostAction; params: Record<string, unknown>};
/** Stable error codes (schemas/host-reply.schema.json). Backend text never reaches JS. */
export type HostErrorCode = 'REQUEST_DENIED' | 'PERMISSION_DENIED' | 'SESSION_EXPIRED' | 'SESSION_REVOKED'
  | 'INVALID_BACKEND_REQUEST' | 'INVALID_PAYLOAD' | 'INVALID_ROUTE' | 'UNSUPPORTED_ACTION'
  | 'BACKEND_UNAUTHENTICATED' | 'BACKEND_FORBIDDEN' | 'BACKEND_NOT_FOUND' | 'BACKEND_CONFLICT'
  | 'BACKEND_VALIDATION_FAILED' | 'BACKEND_RATE_LIMITED' | 'BACKEND_UNAVAILABLE' | 'BACKEND_REQUEST_FAILED'
  | 'NETWORK_UNAVAILABLE' | 'ENCODING_FAILED';
export type HostReply<T = unknown> = {ok: true; data: T} | {ok: false; error: {code: HostErrorCode; message: string}};

/** Native host states a module surface can be in (schemas/host-state.schema.json). */
export type HostState = 'idle' | 'preparing' | 'startingRuntime' | 'loadingModule' | 'ready' | 'suspended'
  | 'failed' | 'unavailable' | 'notInstalled' | 'integrityFailed' | 'updateRequired' | 'permissionDenied' | 'expired';

/** Capabilities a manifest may declare. Actions are also capabilities. */
export const IDENTITY_USER_ID = 'identity.userID';

type Version = [number, number, number];
function parseVersion(value: string): Version | null {
  const match = /^(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})$/.exec(value);
  return match ? [Number(match[1]), Number(match[2]), Number(match[3])] : null;
}
function compare(a: Version, b: Version): number {
  return a[0] - b[0] || a[1] - b[1] || a[2] - b[2];
}
function caretCeiling(v: Version): Version {
  if (v[0] > 0) return [v[0] + 1, 0, 0];
  if (v[1] > 0) return [0, v[1] + 1, 0];
  return [0, 0, v[2] + 1];
}
function evaluate(comparator: string, v: Version): boolean | null {
  if (comparator === '*' || comparator === 'x') return true;
  for (const op of ['>=', '<=', '>', '<', '='] as const) {
    if (!comparator.startsWith(op)) continue;
    const bound = parseVersion(comparator.slice(op.length));
    if (!bound) return null;
    const c = compare(v, bound);
    return op === '>=' ? c >= 0 : op === '<=' ? c <= 0 : op === '>' ? c > 0 : op === '<' ? c < 0 : c === 0;
  }
  if (comparator.startsWith('~')) {
    const bound = parseVersion(comparator.slice(1));
    if (!bound) return null;
    return compare(v, bound) >= 0 && compare(v, [bound[0], bound[1] + 1, 0]) < 0;
  }
  if (comparator.endsWith('.x')) {
    const base = parseVersion(`${comparator.slice(0, -2)}.0`);
    if (!base || comparator.split('.').length !== 3) return null;
    return compare(v, base) >= 0 && compare(v, [base[0], base[1] + 1, 0]) < 0;
  }
  const bound = parseVersion(comparator.startsWith('^') ? comparator.slice(1) : comparator);
  if (!bound) return null;
  return compare(v, bound) >= 0 && compare(v, caretCeiling(bound)) < 0;
}
/**
 * npm-style semver range subset; identical to the Swift `SemverRange`. A bare version is
 * a caret range. Unparseable input never satisfies (fails closed).
 */
export function satisfies(version: string, range: string): boolean {
  const v = parseVersion(version);
  const trimmed = range.trim();
  if (!v || !trimmed || trimmed.length > 128) return false;
  return trimmed.split('||').some(alternative => {
    const comparators = alternative.split(' ').filter(Boolean);
    if (!comparators.length) return false;
    let all = true;
    for (const comparator of comparators) {
      const ok = evaluate(comparator, v);
      if (ok === null) return false;
      all = all && ok;
    }
    return all;
  });
}
/** @deprecated use `satisfies(actual, range)`; kept for existing callers. */
export function compatibleVersion(actual: string, minimum: string): boolean {
  return satisfies(actual, minimum);
}
export function validateManifest(manifest: ModuleManifest): void {
  if (!/^[a-z][a-z0-9.-]+$/.test(manifest.id) || manifest.runtime !== 'react-native'
      || !manifest.entry || !satisfies(HOST_VERSION, manifest.minHostVersion)
      || !satisfies(BRIDGE_VERSION, manifest.minBridgeVersion)) throw new Error('Incompatible module manifest');
}

export type HostAction = 'navigation.open' | 'haptics.selection' | 'diagnostics.ready' | 'diagnostics.dataReady' | 'diagnostics.fail' | 'backend.records.list' | 'backend.records.get' | 'backend.records.create' | 'backend.records.update' | 'backend.records.delete';
