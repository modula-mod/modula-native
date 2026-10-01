import React, {memo, useCallback, useMemo} from 'react';
import {View} from 'react-native';
import type {ModuleTheme} from './theme';
import {ModuleButton, ModuleFallback, ThemedText} from './components';
import {Badge, InlineNotice, RecordRow} from './kit';
import {DataTable, DetailHeader, KeyValueList, Section, SpecForm} from './records';
import {normalizeNodes, type ActionRef, type UINode} from './nodes';

export type ActionHandler = (action: string, payload?: ActionRef['payload'] | Record<string, unknown>) => void;

/**
 * Renders a declarative screen. `actions` maps action names to handlers; only those
 * names survive normalisation, so data can never trigger anything the module did not
 * register. Unknown nodes render as labelled placeholders; one bad node never blanks
 * the screen.
 */
export const NodeRenderer = memo(function NodeRenderer({theme, nodes, actions, testID}: {
  theme: ModuleTheme; nodes: unknown; actions?: Record<string, ActionHandler>; testID?: string;
}) {
  const names = useMemo(() => Object.keys(actions ?? {}), [actions]);
  const tree = useMemo(() => normalizeNodes(nodes, names), [nodes, names]);
  const run = useCallback((ref: ActionRef | undefined, extra?: Record<string, unknown>) => {
    if (!ref) return;
    actions?.[ref.action]?.(ref.action, {...ref.payload, ...extra});
  }, [actions]);
  return <View testID={testID} style={{gap: theme.spacing.md}}>{tree.map(n => <Node key={n.key} theme={theme} node={n} run={run}/>)}</View>;
});

function Node({theme, node, run}: {theme: ModuleTheme; node: UINode; run: (ref: ActionRef | undefined, extra?: Record<string, unknown>) => void}) {
  const children = (list: UINode[]) => list.map(n => <Node key={n.key} theme={theme} node={n} run={run}/>);
  switch (node.type) {
    case 'stack': return <View style={{gap: theme.spacing[node.gap ?? 'md']}}>{children(node.children)}</View>;
    case 'section': return <Section theme={theme} title={node.title} footer={node.footer}>{children(node.children)}</Section>;
    case 'heading': return node.level === 1 ? <DetailHeader theme={theme} title={node.text}/>
      : <ThemedText theme={theme} role={node.level === 2 ? 'title' : 'headline'} accessibilityRole="header">{node.text}</ThemedText>;
    case 'text': return <ThemedText theme={theme} secondary={node.secondary}>{node.text}</ThemedText>;
    case 'badge': return <Badge theme={theme} label={node.label} tone={node.tone}/>;
    case 'notice': return <InlineNotice theme={theme} message={node.message} tone={node.tone}
      action={node.action ? {title: node.action.title, onPress: () => run(node.action)} : undefined}/>;
    case 'button': return <ModuleButton theme={theme} title={node.title} variant={node.variant} onPress={() => run(node.onPress)}/>;
    case 'keyValue': return <KeyValueList theme={theme} items={node.items}/>;
    case 'list': return node.items.length === 0
      ? <ThemedText theme={theme} secondary>{node.empty ?? 'Nothing here yet'}</ThemedText>
      : <View style={{gap: theme.spacing.sm}}>{node.items.map(item => <RecordRow key={item.id} theme={theme} title={item.title}
          subtitle={item.subtitle} meta={item.meta} badges={item.badges} onPress={item.onPress ? () => run(item.onPress) : undefined}/>)}</View>;
    case 'table': {
      const byId = new Map(node.rows.map(r => [r.id, r.onPress]));
      return <DataTable theme={theme} columns={node.columns} rows={node.rows} empty={node.empty}
        onRowPress={node.rows.some(r => r.onPress) ? id => run(byId.get(id)) : undefined}/>;
    }
    case 'form': return <SpecForm theme={theme} fields={node.fields} submitTitle={node.submit.title}
      onSubmit={values => run({action: node.submit.action}, values)}/>;
    case 'empty': return <ModuleFallback theme={theme} title={node.title} message={node.message}
      action={node.action ? {title: node.action.title, onPress: () => run(node.action)} : undefined}/>;
    case 'unsupported': return <View accessible accessibilityLabel={node.label}
      style={{backgroundColor: theme.colors.warningSurface, borderRadius: theme.radius.control, padding: theme.spacing.sm}}>
      <ThemedText theme={theme} role="caption">{node.label}</ThemedText></View>;
  }
}
