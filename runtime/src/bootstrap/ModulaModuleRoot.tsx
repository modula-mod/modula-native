import React, {Component, useEffect, useMemo, useState, type ReactNode} from 'react';
import {Text} from 'react-native';
import {createHost, type Host, type ModuleContext} from '@modula/module-sdk';
import {ModuleRegistry} from '../registry/ModuleRegistry';

class ModuleBoundary extends Component<{host: Host; children: ReactNode}, {failed: boolean}> {
  state = {failed: false};
  static getDerivedStateFromError() { return {failed: true}; }
  componentDidCatch() { void this.props.host.request('diagnostics.fail').catch(() => {}); }
  render() { return this.state.failed ? <Text>Module failed. Use native Retry or Close.</Text> : this.props.children; }
}
function Surface({context: initial, host}: {context: ModuleContext; host: Host}) {
  const [context, setContext] = useState(initial);
  const [lifecycle, setLifecycle] = useState('mounted');
  useEffect(() => host.subscribe(event => {
    setLifecycle(event.name);
    if (event.environment) setContext(current => ({...current, environment: event.environment!}));
  }), [host]);
  useEffect(() => { void host.request('diagnostics.ready').catch(() => {}); }, [host]);
  const entry = ModuleRegistry.get(context.moduleID);
  if (!entry) throw new Error('Unknown module');
  const Module = entry.component;
  return <Module context={context} host={host} lifecycle={lifecycle}/>;
}
export function ModulaModuleRoot(context: ModuleContext) {
  const host = useMemo(() => createHost(context.sessionID), [context.sessionID]);
  return <ModuleBoundary host={host}><Surface context={context} host={host}/></ModuleBoundary>;
}
