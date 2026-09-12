import type {TurboModule, CodegenTypes} from 'react-native';
import {TurboModuleRegistry} from 'react-native';
export interface Spec extends TurboModule {
  request(json: string): Promise<string>;
  readonly onHostEvent: CodegenTypes.EventEmitter<string>;
}
export default TurboModuleRegistry.getEnforcing<Spec>('NativeModulaHost');
