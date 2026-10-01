import React, {memo, useMemo, useState, type ReactNode} from 'react';
import {Pressable, ScrollView, StyleSheet, Switch, TextInput, View} from 'react-native';
import type {ModuleTheme} from './theme';
import {ModuleButton, ThemedText} from './components';
import {Badge, SegmentedControl, type Tone} from './kit';
import {columnWidths, validateForm, type Column, type FieldSpec} from './nodes';

/** Grouped content with an optional header and footer (iOS inset-grouped feel). */
export function Section({theme, title, footer, children}: {theme: ModuleTheme; title?: string; footer?: string; children: ReactNode}) {
  return <View style={{gap: theme.spacing.xs}}>
    {title ? <ThemedText theme={theme} role="caption" secondary accessibilityRole="header" style={styles.caps}>{title}</ThemedText> : null}
    <View style={{gap: theme.spacing.sm}}>{children}</View>
    {footer ? <ThemedText theme={theme} role="caption" secondary>{footer}</ThemedText> : null}
  </View>;
}

/** Title block for a record detail page. */
export function DetailHeader({theme, title, subtitle, badges}: {theme: ModuleTheme; title: string; subtitle?: string; badges?: {label: string; tone?: Tone}[]}) {
  return <View style={{gap: theme.spacing.xs}}>
    <ThemedText theme={theme} role="largeTitle" accessibilityRole="header">{title}</ThemedText>
    {subtitle ? <ThemedText theme={theme} secondary>{subtitle}</ThemedText> : null}
    {badges?.length ? <View style={[styles.row, {gap: theme.spacing.xs, flexWrap: 'wrap'}]}>
      {badges.map(b => <Badge key={b.label} theme={theme} label={b.label} tone={b.tone}/>)}</View> : null}
  </View>;
}

/** Label/value rows (record fields). Each row is one VoiceOver element: "Label, value". */
export function KeyValueList({theme, items}: {theme: ModuleTheme; items: {label: string; value: string}[]}) {
  return <View style={[styles.card, {backgroundColor: theme.colors.surface, borderRadius: theme.radius.card, borderColor: theme.colors.border}]}>
    {items.map((item, index) => <View key={`${item.label}-${index}`} accessible accessibilityLabel={`${item.label}, ${item.value}`}
      style={[styles.kv, {paddingHorizontal: theme.spacing.md, paddingVertical: theme.spacing.sm, minHeight: theme.minimumTouchTarget,
        borderTopWidth: index ? StyleSheet.hairlineWidth : 0, borderTopColor: theme.colors.border, gap: theme.spacing.sm}]}>
      <ThemedText theme={theme} secondary style={styles.kvLabel}>{item.label}</ThemedText>
      <ThemedText theme={theme} style={styles.kvValue}>{item.value}</ThemedText>
    </View>)}
  </View>;
}

/**
 * Horizontally scrollable data table with a sticky-feeling header row. Rows are one
 * accessible element each ("Name: Ada, Stage: Won, …") so VoiceOver reads records,
 * not a grid of loose cells. Keep rows ≤ a page (the node normaliser caps at 500).
 */
export const DataTable = memo(function DataTable({theme, columns, rows, onRowPress, empty = 'No rows', testID}: {
  theme: ModuleTheme; columns: Column[]; rows: {id: string; cells: Record<string, string>}[];
  onRowPress?: (id: string) => void; empty?: string; testID?: string;
}) {
  const widths = useMemo(() => columnWidths(columns, rows), [columns, rows]);
  const cell = (value: string, index: number, header = false) =>
    <View key={columns[index]!.key} style={{width: widths[index], paddingHorizontal: theme.spacing.sm, justifyContent: 'center'}}>
      <ThemedText theme={theme} role={header ? 'caption' : 'body'} secondary={header} numberOfLines={2}
        style={[{textAlign: columns[index]!.align === 'end' ? 'right' : 'left'}, header && styles.caps]}>{value}</ThemedText>
    </View>;
  return <View testID={testID} style={[styles.card, {backgroundColor: theme.colors.surface, borderRadius: theme.radius.card, borderColor: theme.colors.border, overflow: 'hidden'}]}>
    <ScrollView horizontal showsHorizontalScrollIndicator>
      <View>
        <View accessibilityRole="header" style={[styles.row, {minHeight: 36, backgroundColor: theme.colors.surfaceRaised}]}>
          {columns.map((c, i) => cell(c.title, i, true))}
        </View>
        {rows.length === 0 ? <View style={{padding: theme.spacing.md}}><ThemedText theme={theme} secondary>{empty}</ThemedText></View> : null}
        {rows.map((row, r) => {
          const label = columns.map(c => `${c.title}: ${row.cells[c.key] || '—'}`).join(', ');
          const content = columns.map((c, i) => cell(row.cells[c.key] ?? '', i));
          const style = [styles.row, {minHeight: theme.minimumTouchTarget, borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: theme.colors.border,
            backgroundColor: r % 2 && !theme.highContrast ? theme.colors.canvas : theme.colors.surface}];
          return onRowPress
            ? <Pressable key={row.id} accessibilityRole="button" accessibilityLabel={label} onPress={() => onRowPress(row.id)}
                style={({pressed}) => [style, {opacity: pressed && !theme.reduceMotion ? 0.8 : 1}]}>{content}</Pressable>
            : <View key={row.id} accessible accessibilityLabel={label} style={style}>{content}</View>;
        })}
      </View>
    </ScrollView>
  </View>;
});

/** Labelled input with hint and inline error (announced as an alert). */
export function FormField({theme, label, value, onChangeText, multiline, keyboardType, placeholder, hint, error, testID}: {
  theme: ModuleTheme; label: string; value: string; onChangeText: (value: string) => void; multiline?: boolean;
  keyboardType?: 'default' | 'numeric' | 'email-address'; placeholder?: string; hint?: string; error?: string; testID?: string;
}) {
  return <View style={{gap: theme.spacing.xxs}}>
    <ThemedText theme={theme} role="caption" secondary>{label}</ThemedText>
    <TextInput accessibilityLabel={label} accessibilityHint={hint} testID={testID} value={value} onChangeText={onChangeText}
      multiline={multiline} keyboardType={keyboardType} placeholder={placeholder} placeholderTextColor={theme.colors.textSecondary}
      autoCapitalize={keyboardType === 'email-address' ? 'none' : 'sentences'} allowFontScaling maxFontSizeMultiplier={theme.maxFontSizeMultiplier}
      style={[styles.card, {color: theme.colors.text, backgroundColor: theme.colors.surface, borderRadius: theme.radius.control,
        borderColor: error ? theme.colors.danger : theme.colors.border, padding: theme.spacing.sm, fontSize: theme.type.body,
        minHeight: multiline ? 110 : theme.minimumTouchTarget, textAlignVertical: multiline ? 'top' : 'center'}]}/>
    {error ? <ThemedText theme={theme} role="caption" accessibilityRole="alert" style={{color: theme.colors.danger}}>{error}</ThemedText>
      : hint ? <ThemedText theme={theme} role="caption" secondary>{hint}</ThemedText> : null}
  </View>;
}

/** Spec-driven form (used by the node renderer, usable directly). Validates before submit. */
export function SpecForm({theme, fields, submitTitle, initial, onSubmit, busy}: {
  theme: ModuleTheme; fields: FieldSpec[]; submitTitle: string; initial?: Record<string, unknown>;
  onSubmit: (values: Record<string, unknown>) => void; busy?: boolean;
}) {
  const [values, setValues] = useState<Record<string, unknown>>(() => ({...initial}));
  const [errors, setErrors] = useState<Record<string, string>>({});
  const set = (k: string, v: unknown) => { setValues(old => ({...old, [k]: v})); if (errors[k]) setErrors(({[k]: _, ...rest}) => rest); };
  return <View style={{gap: theme.spacing.md}}>
    {fields.map(field => {
      const value = values[field.key];
      if (field.kind === 'toggle') return <View key={field.key} style={[styles.row, {minHeight: theme.minimumTouchTarget, gap: theme.spacing.sm}]}>
        <ThemedText theme={theme} style={{flex: 1}}>{field.label}</ThemedText>
        <Switch accessibilityLabel={field.label} value={value === true} onValueChange={v => set(field.key, v)} trackColor={{true: theme.colors.accent, false: theme.colors.surfaceRaised}}/>
      </View>;
      if (field.kind === 'choice') return <View key={field.key} style={{gap: theme.spacing.xxs}}>
        <ThemedText theme={theme} role="caption" secondary>{field.label}</ThemedText>
        <SegmentedControl theme={theme} label={field.label} options={field.options ?? []} value={typeof value === 'string' ? value : ''} onChange={v => set(field.key, v)}/>
        {errors[field.key] ? <ThemedText theme={theme} role="caption" accessibilityRole="alert" style={{color: theme.colors.danger}}>{errors[field.key]}</ThemedText> : null}
      </View>;
      return <FormField key={field.key} theme={theme} label={field.required ? `${field.label} (required)` : field.label} value={value === undefined || value === null ? '' : String(value)}
        onChangeText={v => set(field.key, v)} multiline={field.kind === 'multiline'} placeholder={field.placeholder} hint={field.hint} error={errors[field.key]}
        keyboardType={field.kind === 'number' ? 'numeric' : field.kind === 'email' ? 'email-address' : 'default'}/>;
    })}
    <ModuleButton theme={theme} title={submitTitle} disabled={busy} onPress={() => {
      const found = validateForm(fields, values);
      setErrors(found);
      if (!Object.keys(found).length) onSubmit(values);
    }}/>
  </View>;
}

const styles = StyleSheet.create({
  row: {flexDirection: 'row', alignItems: 'center'},
  card: {borderWidth: StyleSheet.hairlineWidth},
  caps: {textTransform: 'uppercase', letterSpacing: 0.4},
  kv: {flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap'},
  kvLabel: {flexBasis: 120, flexGrow: 0, flexShrink: 0},
  kvValue: {flex: 1, minWidth: 140, textAlign: 'left'},
});
