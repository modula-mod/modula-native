import {AppRegistry, LogBox} from 'react-native';
import {ModulaModuleRoot} from './src/bootstrap/ModulaModuleRoot';
// Embedded surfaces must never open LogBox's app-wide window. Errors remain
// in the JS console and are reported to ModuleHost by the module boundary.
if (__DEV__) LogBox.uninstall();
AppRegistry.registerComponent('ModulaModuleRoot', () => ModulaModuleRoot);
