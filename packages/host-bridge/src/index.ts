import NativeHost from './specs/NativeModulaHost';
import {BRIDGE_VERSION, type HostEvent, type HostAction} from '@modula/module-contracts';
export function createHost(sessionID: string, moduleID: string) {
  return {
    async request<T = unknown>(action: HostAction, params: Record<string, unknown> = {}): Promise<T> {
      const wire = await NativeHost.request(JSON.stringify({version: BRIDGE_VERSION, sessionID, moduleID, action, params}));
      const result = JSON.parse(wire) as {ok: boolean; data?: T; error?: {code: string; message: string}};
      if (!result.ok) throw new Error(result.error?.message ?? 'Host request rejected');
      return result.data as T;
    },
    subscribe(listener: (event: HostEvent) => void) {
      const subscription = NativeHost.onHostEvent(wire => {
        const event = JSON.parse(wire) as HostEvent;
        if (event.sessionID === sessionID) listener(event);
      });
      return () => subscription.remove();
    },
  };
}
export type Host = ReturnType<typeof createHost>;
