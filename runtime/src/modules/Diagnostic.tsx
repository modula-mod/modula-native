import React, {useState, useEffect, useRef} from 'react';
import {View, Text, Button, ScrollView} from 'react-native';
import type {HostAction} from '@modula/module-contracts';
import type {Host, ModuleContext} from '@modula/module-sdk';

export function Diagnostic({context, host, lifecycle}: {context: ModuleContext; host: Host; lifecycle: string}) {
  const alive = useRef(true);
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);
  const [result, setResult] = useState('Ready');
  const [crash, setCrash] = useState(false);
  if (crash) throw new Error('Intentional diagnostic render failure');
  async function request(action: HostAction, params = {}) {
    try { await host.request(action, params); if (alive.current) setResult('Native action accepted'); }
    catch { if (alive.current) setResult('Invalid action safely rejected'); }
  }
  const dark = context.environment.colorScheme === 'dark';
  return <ScrollView style={{flex: 1, backgroundColor: context.environment.oled ? '#000000' : dark ? '#17191b' : '#ffffff'}} contentContainerStyle={{padding: 24, gap: 18}}>
    <Text accessibilityRole="header" style={{fontSize: 24, fontWeight: '700', color: dark ? '#fff' : '#111'}}>Module runtime ready</Text>
    <Text style={{color: dark ? '#fff' : '#111'}}>{context.moduleID}</Text>
    <Text testID="diagnostic.environment" style={{color: dark ? '#fff' : '#111'}}>Appearance: {context.environment.colorScheme} · OLED {String(context.environment.oled)}</Text>
    <Text testID="diagnostic.lifecycle" style={{color: dark ? '#fff' : '#111'}}>Lifecycle: {lifecycle}</Text>
    <View style={{gap: 12}}>
      <Button title="Open native Profile" onPress={() => void request('navigation.open', {route: 'profile', userId: context.userID ?? 'me'})}/>
      <Button title="Native haptic" onPress={() => void request('haptics.selection')}/>
      <Button title="Reject invalid action" onPress={() => void request('navigation.open', {route: 'platform.takeOwnership'})}/>
      <Button title="Throw module error" onPress={() => setCrash(true)}/>
    </View>
    <Text accessibilityRole="alert" style={{color: dark ? '#fff' : '#111'}}>{result}</Text>
  </ScrollView>;
}
