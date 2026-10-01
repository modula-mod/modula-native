import {designContract} from '../../../packages/design-contracts/src/generated';
import type {ModuleEnvironment} from '@modula/module-contracts';

/** Resolved, render-ready tokens for a module surface. Pure: safe for tests and memoisation. */
export type ModuleTheme = {
  dark: boolean;
  colors: {
    canvas: string; surface: string; surfaceRaised: string; border: string;
    text: string; textSecondary: string; accent: string; onAccent: string;
    danger: string; warningSurface: string;
  };
  spacing: {xxs: number; xs: number; sm: number; md: number; lg: number; xl: number};
  radius: {control: number; card: number};
  type: {largeTitle: number; title: number; headline: number; body: number; caption: number};
  /** Upper bound passed to `maxFontSizeMultiplier` so AX sizes grow but layouts survive. */
  maxFontSizeMultiplier: number;
  textScale: number;
  minimumTouchTarget: number;
  reduceMotion: boolean;
  highContrast: boolean;
};

const HEX = /^#[0-9a-f]{6}$/i;

function luminance(hex: string): number {
  const channel = (offset: number) => {
    const value = parseInt(hex.slice(offset, offset + 2), 16) / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5);
}

function clamp(value: number, min: number, max: number): number {
  return Number.isFinite(value) ? Math.min(Math.max(value, min), max) : 1;
}

export function moduleTheme(environment?: Partial<ModuleEnvironment> | null): ModuleTheme {
  const env = environment ?? {};
  const dark = env.colorScheme === 'dark';
  const oled = dark && (env.oled === true || env.darkStyle === 'oled');
  const highContrast = env.contrastPreference === 'higherContrast';
  const accent = typeof env.accent === 'string' && HEX.test(env.accent) ? env.accent : designContract.colors['accent.default'];
  const density = env.density === 'compact' ? designContract.density.compact
    : env.density === 'comfortable' ? designContract.density.comfortable : designContract.density.standard;
  const space = (value: number) => Math.round(value * density);
  const radius = env.interfaceShape === 'precise' ? designContract.radius.small
    : env.interfaceShape === 'soft' ? designContract.radius.large : designContract.radius.medium;
  const textScale = clamp(typeof env.textScale === 'number' ? env.textScale : 1, 0.8, 3.2);
  return {
    dark,
    colors: {
      canvas: oled ? designContract.colors['canvas.oled'] : dark ? '#15191A' : '#F5F8F8',
      surface: oled ? '#0E1112' : dark ? '#202829' : '#FFFFFF',
      surfaceRaised: oled ? '#161B1C' : dark ? '#2A3436' : '#EEF3F3',
      border: highContrast ? (dark ? '#9AA7A9' : '#4A5759') : dark ? 'rgba(255,255,255,0.10)' : 'rgba(23,36,38,0.08)',
      text: dark ? '#F5F8F8' : '#172426',
      textSecondary: highContrast ? (dark ? '#E1E8E9' : '#2B3A3C') : dark ? '#A9B6B8' : '#5B6B6D',
      accent,
      onAccent: luminance(accent) > 0.45 ? '#0B1213' : '#FFFFFF',
      danger: dark ? '#FF8A80' : '#B3261E',
      warningSurface: dark ? '#3A2E14' : '#FFF4D6',
    },
    spacing: {
      xxs: space(designContract.spacing.xxs), xs: space(designContract.spacing.xs), sm: space(designContract.spacing.sm),
      md: space(designContract.spacing.md), lg: space(designContract.spacing.lg), xl: space(designContract.spacing.xl),
    },
    radius: {control: Math.max(8, radius - 4), card: radius},
    type: {largeTitle: 30, title: 22, headline: 17, body: 16, caption: 13},
    maxFontSizeMultiplier: Math.max(1.6, Math.min(textScale * 1.25, 3.2)),
    textScale,
    minimumTouchTarget: designContract.density.minimumTouchTarget,
    reduceMotion: env.reduceMotion === true,
    highContrast,
  };
}
