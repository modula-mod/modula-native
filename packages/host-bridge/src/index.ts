import NativeHost from './specs/NativeModulaHost';
import {BRIDGE_VERSION, type HostEvent, type HostAction, type HostErrorCode} from '@modula/module-contracts';

export class HostError extends Error {
  constructor(readonly code: HostErrorCode, message: string) { super(message); }
}

/**
 * One host per surface. Requests carry the surface's native-issued token; events are not
 * read from a shared emitter but delivered by the root component from this surface's own
 * props (`deliver`), so no module ever sees another surface's events or token.
 */
export function createHost(surfaceToken: string, moduleID: string) {
  const listeners = new Set<(event: HostEvent) => void>();
  let lastSequence = -1;
  return {
    async request<T = unknown>(action: HostAction, params: Record<string, unknown> = {}): Promise<T> {
      const wire = await NativeHost.request(JSON.stringify({version: BRIDGE_VERSION, surfaceToken, moduleID, action, params}));
      const result = JSON.parse(wire) as {ok: boolean; data?: T; error?: {code: HostErrorCode; message: string}};
      if (!result.ok) throw new HostError(result.error?.code ?? 'REQUEST_DENIED', result.error?.message ?? 'Host request rejected');
      return result.data as T;
    },
    subscribe(listener: (event: HostEvent) => void) {
      listeners.add(listener);
      return () => { listeners.delete(listener); };
    },
    /** Internal: called by ModulaModuleRoot when this surface's props carry a new event. */
    deliver(event: HostEvent) {
      if (event.sequence <= lastSequence) return;
      lastSequence = event.sequence;
      listeners.forEach(listener => listener(event));
    },
  };
}
export type Host = ReturnType<typeof createHost>;
