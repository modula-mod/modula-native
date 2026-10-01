import React, {Component, useEffect, useMemo, useState, type ReactNode} from 'react';
import {View} from 'react-native';
import {createHost, type Host, type ModuleContext, type ModuleEnvironment} from '@modula/module-sdk';
import {ModuleRegistry} from '../registry/ModuleRegistry';
import {moduleTheme} from '../ui/theme';
import {ModuleFallback} from '../ui/components';

/** Catches render errors and shows a themed, accessible fallback instead of bare text. */
class ModuleBoundary extends Component<{host: Host; environment: ModuleEnvironment; children: ReactNode}, {failed: boolean}> {
  state = {failed: false};
  static getDerivedStateFromError() { return {failed: true}; }
  componentDidCatch() { void this.props.host.request('diagnostics.fail').catch(() => {}); }
  render() {
    if (!this.state.failed) return this.props.children;
    const theme = moduleTheme(this.props.environment);
    return <View style={{flex: 1, backgroundColor: theme.colors.canvas}}>
      <ModuleFallback theme={theme} testID="module.failed" title="This module stopped working"
        message="Use Retry or Close above. Your data is safe." action={{title: 'Try again', onPress: () => this.setState({failed: false})}}/>
    </View>;
  }
}

function Surface({context: initial, host}: {context: ModuleContext; host: Host}) {
  const [context, setContext] = useState(initial);
  const [lifecycle, setLifecycle] = useState('mounted');
  const entry = ModuleRegistry.get(context.moduleID);
  useEffect(() => host.subscribe(event => {
    setLifecycle(event.name);
    if (event.environment) setContext(current => ({...current, environment: event.environment!}));
  }), [host]);
  // Unknown modules report failure so the native host doesn't wait for the 20s watchdog.
  useEffect(() => { void host.request(entry ? 'diagnostics.ready' : 'diagnostics.fail').catch(() => {}); }, [host, entry]);
  if (!entry) {
    const theme = moduleTheme(context.environment);
    return <View style={{flex: 1, backgroundColor: theme.colors.canvas}}>
      <ModuleFallback theme={theme} testID="module.unknown" title="Module unavailable"
        message="This module isn’t included in this version of Modula. Update the app or close it."/>
    </View>;
  }
  const Module = entry.component;
  return <Module context={context} host={host} lifecycle={lifecycle}/>;
}

export function ModulaModuleRoot(context: ModuleContext) {
  const host = useMemo(() => createHost(context.sessionID, context.moduleID), [context.sessionID, context.moduleID]);
  return <ModuleBoundary host={host} environment={context.environment}><Surface context={context} host={host}/></ModuleBoundary>;
}
