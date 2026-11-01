import React, {memo, type ReactNode} from 'react';
import {Pressable, StyleSheet, Switch, Text, TextInput, View, type StyleProp, type ViewStyle} from 'react-native';
import type {ModuleTheme} from './theme';
import {ModuleButton, ThemedText} from './components';

/**
 * Reusable module building blocks. Every component takes the resolved theme, meets the
 * 44pt touch target, scales with Dynamic Type (capped by the theme) and exposes an
 * accessibility role/label/state. Modules compose these; none of them talk to the host.
 */

export type Tone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger';

function toneColors(theme: ModuleTheme, tone: Tone): {background: string; foreground: string} {
  switch (tone) {
    case 'accent': return {background: theme.colors.surfaceRaised, foreground: theme.colors.accent};
    case 'success': return {background: theme.dark ? '#163A2A' : '#E3F4EA', foreground: theme.dark ? '#7FD8A5' : '#1E6B43'};
    case 'warning': return {background: theme.colors.warningSurface, foreground: theme.dark ? '#F3CF7A' : '#7A5600'};
    case 'danger': return {background: theme.dark ? '#3D1A18' : '#FBE9E7', foreground: theme.colors.danger};
    default: return {background: theme.colors.surfaceRaised, foreground: theme.colors.textSecondary};
  }
}

export function Badge({theme, label, tone = 'neutral'}: {theme: ModuleTheme; label: string; tone?: Tone}) {
  const colors = toneColors(theme, tone);
  return <View accessible accessibilityLabel={label}
    style={{backgroundColor: colors.background, borderRadius: 999, paddingHorizontal: theme.spacing.xs, paddingVertical: 2, alignSelf: 'flex-start'}}>
    <Text allowFontScaling maxFontSizeMultiplier={theme.maxFontSizeMultiplier}
      style={{color: colors.foreground, fontSize: theme.type.caption, fontWeight: '600'}}>{label}</Text>
  </View>;
}

/** Search input with a clear button. Debounce in the caller (see `useDebounced`). */
export function SearchField({theme, value, onChangeText, placeholder = 'Search', label, testID}: {
  theme: ModuleTheme; value: string; onChangeText: (value: string) => void; placeholder?: string; label: string; testID?: string;
}) {
  return <View style={[styles.row, {backgroundColor: theme.colors.surfaceRaised, borderRadius: theme.radius.control,
    paddingHorizontal: theme.spacing.sm, minHeight: theme.minimumTouchTarget, gap: theme.spacing.xs}]}>
    <Text accessible={false} style={{color: theme.colors.textSecondary, fontSize: theme.type.body}}>⌕</Text>
    <TextInput value={value} onChangeText={onChangeText} placeholder={placeholder} placeholderTextColor={theme.colors.textSecondary}
      accessibilityLabel={label} testID={testID} returnKeyType="search" autoCorrect={false} autoCapitalize="none" clearButtonMode="never"
      allowFontScaling maxFontSizeMultiplier={theme.maxFontSizeMultiplier} maxLength={200}
      style={{flex: 1, color: theme.colors.text, fontSize: theme.type.body, paddingVertical: theme.spacing.xs}}/>
    {value.length > 0 && <Pressable accessibilityRole="button" accessibilityLabel="Clear search" onPress={() => onChangeText('')}
      hitSlop={8} style={styles.clear}>
      <Text style={{color: theme.colors.textSecondary, fontSize: theme.type.body}}>✕</Text>
    </Pressable>}
  </View>;
}

/** Single-choice segmented control (sort, filter, tabs). Reports selection to VoiceOver. */
export function SegmentedControl<T extends string>({theme, options, value, onChange, label}: {
  theme: ModuleTheme; options: {value: T; label: string}[]; value: T; onChange: (value: T) => void; label: string;
}) {
  return <View accessibilityRole="tablist" accessibilityLabel={label}
    style={[styles.row, {backgroundColor: theme.colors.surfaceRaised, borderRadius: theme.radius.control, padding: 2, flexWrap: 'wrap'}]}>
    {options.map(option => {
      const selected = option.value === value;
      return <Pressable key={option.value} accessibilityRole="tab" accessibilityLabel={option.label} accessibilityState={{selected}}
        onPress={() => { if (!selected) onChange(option.value); }}
        style={{flexGrow: 1, minHeight: theme.minimumTouchTarget - 4, justifyContent: 'center', alignItems: 'center',
          paddingHorizontal: theme.spacing.sm, borderRadius: Math.max(6, theme.radius.control - 2),
          backgroundColor: selected ? theme.colors.surface : 'transparent',
          borderWidth: selected && theme.highContrast ? 1 : 0, borderColor: theme.colors.border}}>
        <Text allowFontScaling maxFontSizeMultiplier={theme.maxFontSizeMultiplier}
          style={{color: selected ? theme.colors.text : theme.colors.textSecondary, fontSize: theme.type.caption + 1, fontWeight: selected ? '600' : '500'}}>
          {option.label}</Text>
      </Pressable>;
    })}
  </View>;
}

/**
 * A record in a list: title, optional subtitle/meta, badges and a trailing accessory.
 * Memoised; pass stable callbacks. Accessibility label is the title so tests and
 * VoiceOver find rows by name; subtitle and meta are read as the hint.
 */
export const RecordRow = memo(function RecordRow({theme, title, subtitle, meta, badges, leading, onPress, onLongPress, longPressLabel, testID}: {
  theme: ModuleTheme; title: string; subtitle?: string; meta?: string; badges?: {label: string; tone?: Tone}[];
  leading?: ReactNode; onPress?: () => void; onLongPress?: () => void; longPressLabel?: string; testID?: string;
}) {
  const hint = [subtitle, meta].filter(Boolean).join('. ').slice(0, 160) || undefined;
  const body = <>
    {leading}
    <View style={{flex: 1, gap: theme.spacing.xxs}}>
      <ThemedText theme={theme} role="headline" numberOfLines={2}>{title}</ThemedText>
      {subtitle ? <ThemedText theme={theme} secondary numberOfLines={2}>{subtitle}</ThemedText> : null}
      {(meta || badges?.length) ? <View style={[styles.row, {gap: theme.spacing.xs, flexWrap: 'wrap', marginTop: 2}]}>
        {badges?.map(badge => <Badge key={badge.label} theme={theme} label={badge.label} tone={badge.tone}/>)}
        {meta ? <ThemedText theme={theme} role="caption" secondary>{meta}</ThemedText> : null}
      </View> : null}
    </View>
  </>;
  const style: StyleProp<ViewStyle> = [styles.row, styles.card, {backgroundColor: theme.colors.surface, borderRadius: theme.radius.card,
    padding: theme.spacing.md, gap: theme.spacing.sm, minHeight: 72, borderColor: theme.colors.border, alignItems: 'flex-start'}];
  if (!onPress) return <View style={style} testID={testID}>{body}</View>;
  // Long press is mirrored as a VoiceOver custom action so it is never a hidden-only gesture.
  const actions = onLongPress && longPressLabel ? [{name: 'longpress', label: longPressLabel}] : undefined;
  return <Pressable accessibilityRole="button" accessibilityLabel={title} accessibilityHint={hint} onPress={onPress} testID={testID}
    onLongPress={onLongPress} accessibilityActions={actions}
    onAccessibilityAction={event => { if (event.nativeEvent.actionName === 'longpress') onLongPress?.(); }}
    style={({pressed}) => [style, {opacity: pressed && !theme.reduceMotion ? 0.85 : 1}]}>{body}</Pressable>;
});

/** Static placeholder rows for first load (no shimmer, so it is Reduce Motion safe). */
export function SkeletonRows({theme, count = 3}: {theme: ModuleTheme; count?: number}) {
  const bar = (width: `${number}%`, height: number) =>
    <View style={{width, height, borderRadius: 4, backgroundColor: theme.colors.surfaceRaised}}/>;
  return <View accessible={false} importantForAccessibility="no-hide-descendants" style={{gap: theme.spacing.sm}}>
    {Array.from({length: count}, (_, index) => <View key={index} style={[styles.card, {backgroundColor: theme.colors.surface,
      borderRadius: theme.radius.card, padding: theme.spacing.md, gap: theme.spacing.xs, borderColor: theme.colors.border}]}>
      {bar(index % 2 ? '55%' : '70%', 16)}{bar('90%', 12)}{bar('40%', 12)}
    </View>)}
  </View>;
}

/** Inline, non-blocking notice (e.g. "Couldn’t load more" with Try again). */
export function InlineNotice({theme, message, tone = 'warning', action, testID}: {
  theme: ModuleTheme; message: string; tone?: Tone; action?: {title: string; onPress: () => void}; testID?: string;
}) {
  const colors = toneColors(theme, tone);
  return <View testID={testID} style={[styles.row, {backgroundColor: colors.background, borderRadius: theme.radius.control,
    padding: theme.spacing.sm, gap: theme.spacing.sm, flexWrap: 'wrap'}]}>
    <Text accessibilityRole="alert" allowFontScaling maxFontSizeMultiplier={theme.maxFontSizeMultiplier}
      style={{flex: 1, minWidth: 160, color: colors.foreground, fontSize: theme.type.caption + 1}}>{message}</Text>
    {action && <ModuleButton theme={theme} title={action.title} variant="secondary" onPress={action.onPress}/>}
  </View>;
}

export function ToggleRow({theme, label, value, onChange, disabled, testID}: {
  theme: ModuleTheme; label: string; value: boolean; onChange: (value: boolean) => void; disabled?: boolean; testID?: string;
}) {
  return <View style={[styles.row, {minHeight: theme.minimumTouchTarget, gap: theme.spacing.sm}]}>
    <ThemedText theme={theme} style={{flex: 1}}>{label}</ThemedText>
    <Switch accessibilityLabel={label} testID={testID} value={value} onValueChange={onChange} disabled={disabled}
      trackColor={{true: theme.colors.accent, false: theme.colors.surfaceRaised}}/>
  </View>;
}

export function Toolbar({theme, children}: {theme: ModuleTheme; children: ReactNode}) {
  return <View accessibilityRole="toolbar" style={[styles.row, {gap: theme.spacing.sm, flexWrap: 'wrap'}]}>{children}</View>;
}

const styles = StyleSheet.create({
  row: {flexDirection: 'row', alignItems: 'center'},
  card: {borderWidth: StyleSheet.hairlineWidth},
  clear: {minWidth: 32, minHeight: 32, alignItems: 'center', justifyContent: 'center'},
});
