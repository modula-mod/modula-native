import React, {memo, type ReactNode} from 'react';
import {ActivityIndicator, Linking, Pressable, StyleSheet, Text, View, type StyleProp, type TextStyle, type ViewStyle} from 'react-native';
import type {ModuleTheme} from './theme';
import type {BlockModel} from './blocks';

type TextRole = 'largeTitle' | 'title' | 'headline' | 'body' | 'caption';

/** Dynamic Type aware text: scales with the host text size, capped by the theme. */
export function ThemedText({theme, role = 'body', secondary, style, children, ...rest}: {
  theme: ModuleTheme; role?: TextRole; secondary?: boolean; style?: StyleProp<TextStyle>; children?: ReactNode;
  testID?: string; numberOfLines?: number; accessibilityRole?: 'header' | 'alert' | 'text'; accessibilityLabel?: string;
}) {
  const weight: TextStyle['fontWeight'] = role === 'largeTitle' ? '700' : role === 'title' || role === 'headline' ? '600' : '400';
  return <Text
    allowFontScaling
    maxFontSizeMultiplier={theme.maxFontSizeMultiplier}
    style={[{color: secondary ? theme.colors.textSecondary : theme.colors.text, fontSize: theme.type[role], fontWeight: weight,
      lineHeight: Math.round(theme.type[role] * 1.3)}, style]}
    {...rest}>{children}</Text>;
}

/** 44pt minimum, labelled, state-reporting button built from design tokens. */
export function ModuleButton({theme, title, onPress, disabled, variant = 'primary', testID, accessibilityHint}: {
  theme: ModuleTheme; title: string; onPress: () => void; disabled?: boolean;
  variant?: 'primary' | 'secondary' | 'destructive'; testID?: string; accessibilityHint?: string;
}) {
  const background = variant === 'primary' ? theme.colors.accent : theme.colors.surfaceRaised;
  const foreground = variant === 'primary' ? theme.colors.onAccent : variant === 'destructive' ? theme.colors.danger : theme.colors.accent;
  return <Pressable
    accessibilityRole="button"
    accessibilityLabel={title}
    accessibilityHint={accessibilityHint}
    accessibilityState={{disabled: Boolean(disabled)}}
    disabled={disabled}
    testID={testID}
    onPress={onPress}
    hitSlop={4}
    style={({pressed}) => [styles.button, {
      minHeight: theme.minimumTouchTarget, borderRadius: theme.radius.control, backgroundColor: background,
      paddingHorizontal: theme.spacing.md, opacity: disabled ? 0.45 : pressed && !theme.reduceMotion ? 0.82 : 1,
      borderWidth: theme.highContrast ? 1 : 0, borderColor: theme.colors.border,
    }]}>
    <Text allowFontScaling maxFontSizeMultiplier={theme.maxFontSizeMultiplier}
      style={{color: foreground, fontSize: theme.type.body, fontWeight: '600'}}>{title}</Text>
  </Pressable>;
}

export function ModuleCard({theme, children, style}: {theme: ModuleTheme; children: ReactNode; style?: StyleProp<ViewStyle>}) {
  return <View style={[{backgroundColor: theme.colors.surface, borderRadius: theme.radius.card, padding: theme.spacing.md,
    gap: theme.spacing.xs, borderWidth: StyleSheet.hairlineWidth, borderColor: theme.colors.border}, style]}>{children}</View>;
}

/** Spinner, or a static label when Reduce Motion is on. */
export function LoadingRow({theme, label}: {theme: ModuleTheme; label: string}) {
  return <View accessible accessibilityRole="progressbar" accessibilityLabel={label} style={[styles.row, {gap: theme.spacing.xs, minHeight: theme.minimumTouchTarget}]}>
    {!theme.reduceMotion && <ActivityIndicator color={theme.colors.accent}/>}
    <ThemedText theme={theme} role="caption" secondary>{label}</ThemedText>
  </View>;
}

/** Shared empty / error / unsupported surface. Never blank. */
export function ModuleFallback({theme, title, message, action, testID}: {
  theme: ModuleTheme; title: string; message: string; action?: {title: string; onPress: () => void}; testID?: string;
}) {
  return <View testID={testID} style={[styles.fallback, {padding: theme.spacing.lg, gap: theme.spacing.sm}]}>
    <View style={{gap: theme.spacing.xs, alignItems: 'center'}}>
      <View accessible={false} importantForAccessibility="no" style={[styles.glyph, {backgroundColor: theme.colors.surfaceRaised, borderRadius: theme.radius.card}]}>
        <Text accessible={false} allowFontScaling={false} style={{fontSize: 26, color: theme.colors.accent}}>◇</Text>
      </View>
      <ThemedText theme={theme} role="headline" accessibilityRole="header" style={styles.center}>{title}</ThemedText>
      {/* Separate elements so VoiceOver reads the message as an alert and tests can find it verbatim. */}
      <ThemedText theme={theme} role="body" secondary accessibilityRole="alert" style={styles.center}>{message}</ThemedText>
    </View>
    {action && <ModuleButton theme={theme} title={action.title} onPress={action.onPress} variant="secondary"/>}
  </View>;
}

/** Read-only renderer for structured note documents with per-block fallbacks. */
export const DocumentBlocks = memo(function DocumentBlocks({theme, blocks}: {theme: ModuleTheme; blocks: BlockModel[]}) {
  return <View style={{gap: theme.spacing.sm}} testID="vault.document">{blocks.map(block => <Block key={block.key} theme={theme} block={block}/>)}</View>;
});

function Block({theme, block}: {theme: ModuleTheme; block: BlockModel}) {
  switch (block.kind) {
    case 'heading':
      return <ThemedText theme={theme} role={block.level === 1 ? 'title' : 'headline'} accessibilityRole="header">{block.text}</ThemedText>;
    case 'paragraph':
      return <ThemedText theme={theme}>{block.text}</ThemedText>;
    case 'quote':
      return <View style={{borderLeftWidth: 3, borderLeftColor: theme.colors.accent, paddingLeft: theme.spacing.sm}}>
        <ThemedText theme={theme} style={{fontStyle: 'italic'}}>{block.text}</ThemedText></View>;
    case 'callout':
      return <View style={{backgroundColor: theme.colors.surfaceRaised, borderRadius: theme.radius.control, padding: theme.spacing.sm}}>
        <ThemedText theme={theme}>{block.text}</ThemedText></View>;
    case 'code':
      return <View style={{backgroundColor: theme.colors.surfaceRaised, borderRadius: theme.radius.control, padding: theme.spacing.sm}}>
        <ThemedText theme={theme} role="caption" style={{fontFamily: 'Menlo'}}>{block.text}</ThemedText></View>;
    case 'list':
      return <View style={{gap: theme.spacing.xxs}}>{block.items.map((item, index) =>
        <ThemedText key={index} theme={theme}>{block.ordered ? `${index + 1}.` : '•'} {item}</ThemedText>)}</View>;
    case 'checklist':
      return <View style={{gap: theme.spacing.xxs}}>{block.items.map((item, index) =>
        <ThemedText key={index} theme={theme} accessibilityLabel={`${item.checked ? 'Done' : 'Not done'}, ${item.text}`}>
          {item.checked ? '☑' : '☐'} {item.text}</ThemedText>)}</View>;
    case 'divider':
      return <View accessible={false} style={{height: StyleSheet.hairlineWidth, backgroundColor: theme.colors.border}}/>;
    case 'link':
      return <Pressable accessibilityRole="link" accessibilityLabel={block.title} onPress={() => void Linking.openURL(block.url).catch(() => {})}
        style={{minHeight: theme.minimumTouchTarget, justifyContent: 'center'}}>
        <ThemedText theme={theme} style={{color: theme.colors.accent, textDecorationLine: 'underline'}}>{block.title}</ThemedText></Pressable>;
    case 'reference':
      return <ThemedText theme={theme} secondary>{block.label}: {block.detail}</ThemedText>;
    case 'unsupported':
      return <View accessible accessibilityLabel={block.label}
        style={{backgroundColor: theme.colors.warningSurface, borderRadius: theme.radius.control, padding: theme.spacing.sm}}>
        <ThemedText theme={theme} role="caption">{block.label}</ThemedText></View>;
  }
}

const styles = StyleSheet.create({
  button: {alignItems: 'center', justifyContent: 'center'},
  row: {flexDirection: 'row', alignItems: 'center'},
  fallback: {flex: 1, justifyContent: 'center'},
  glyph: {width: 56, height: 56, alignItems: 'center', justifyContent: 'center'},
  center: {textAlign: 'center'},
});
