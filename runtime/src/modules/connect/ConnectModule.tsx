import React, {useCallback, useEffect, useMemo, useRef, useState, type ReactNode} from 'react';
import {Pressable, ScrollView, Share, StyleSheet, Text, View} from 'react-native';
import type {Host, ModuleContext} from '@modula/module-sdk';
import {moduleTheme, type ModuleTheme} from '../../ui/theme';
import {LoadingRow, ModuleCard, ThemedText} from '../../ui/components';
import {Badge, InlineNotice, SearchField, SegmentedControl, ToggleRow} from '../../ui/kit';
import {FormField, KeyValueList, Section} from '../../ui/records';
import {useAlive} from '../../ui/hooks';
import {
  capabilityLabel, createMockConnectApi, filterNumbers, formatPrice, lifecycleLabel, recurringTotal, STEP_TITLES, typeLabel,
  validateCompliance, type AvailableNumber, type ComplianceForm, type ConnectApi, type Country, type IdentityKind,
  type NumberType, type OwnedNumber, type Plan, type Step, type VerificationStatus,
  isMemorable, mockUsage, usageFraction, lifecycleProgress, LIFECYCLE_ORDER,
} from './model';

/**
 * Modula Connect (spec v1.0) — PREVIEW on mock data. Screens 01–12 plus number settings.
 * Never calls a carrier, never charges, and never claims a number is really active.
 */

// Black/white actions (no accent fills), per the native design rules.
function Action({theme, title, onPress, disabled, secondary, testID}: {
  theme: ModuleTheme; title: string; onPress: () => void; disabled?: boolean; secondary?: boolean; testID?: string;
}) {
  const fill = theme.dark ? '#FFFFFF' : '#0B0B0B';
  const ink = theme.dark ? '#0B0B0B' : '#FFFFFF';
  return <Pressable accessibilityRole="button" accessibilityLabel={title} accessibilityState={{disabled: Boolean(disabled)}}
    disabled={disabled} onPress={onPress} testID={testID} hitSlop={4}
    style={({pressed}) => [styles.action, {minHeight: theme.minimumTouchTarget + 6, borderRadius: 999,
      backgroundColor: secondary ? theme.colors.surfaceRaised : fill,
      opacity: disabled ? 0.4 : pressed && !theme.reduceMotion ? 0.8 : 1,
      borderWidth: theme.highContrast || secondary ? StyleSheet.hairlineWidth : 0, borderColor: theme.colors.border}]}>
    <Text allowFontScaling maxFontSizeMultiplier={theme.maxFontSizeMultiplier}
      style={{color: secondary ? theme.colors.text : ink, fontSize: theme.type.body, fontWeight: '600', textAlign: 'center'}}>{title}</Text>
  </Pressable>;
}

function Choice({theme, title, subtitle, onPress, selected, disabled, trailing, testID}: {
  theme: ModuleTheme; title: string; subtitle?: string; onPress?: () => void; selected?: boolean; disabled?: boolean;
  trailing?: ReactNode; testID?: string;
}) {
  return <Pressable accessibilityRole="button" accessibilityLabel={title} accessibilityHint={subtitle}
    accessibilityState={{selected: Boolean(selected), disabled: Boolean(disabled)}} disabled={disabled || !onPress} onPress={onPress} testID={testID}
    style={({pressed}) => [styles.row, styles.choice, {backgroundColor: theme.colors.surface, borderRadius: theme.radius.card,
      padding: theme.spacing.md, gap: theme.spacing.sm, minHeight: 64, opacity: disabled ? 0.5 : pressed && !theme.reduceMotion ? 0.85 : 1,
      borderColor: selected ? theme.colors.text : theme.colors.border, borderWidth: selected ? 2 : StyleSheet.hairlineWidth}]}>
    <View style={{flex: 1, gap: 2}}>
      <ThemedText theme={theme} role="headline">{title}</ThemedText>
      {subtitle ? <ThemedText theme={theme} secondary>{subtitle}</ThemedText> : null}
    </View>
    {trailing}
  </Pressable>;
}

/** Modula Connect mark + wordmark (black/white, matches the native logo). */
function ConnectLogo({theme, size = 40, tagline = false}: {theme: ModuleTheme; size?: number; tagline?: boolean}) {
  const fill = theme.dark ? '#FFFFFF' : '#0B0B0B';
  const ink = theme.dark ? '#0B0B0B' : '#FFFFFF';
  const arc = (r: number) => ({position: 'absolute' as const, width: r * 2, height: r * 2, borderRadius: r,
    borderWidth: Math.max(1.6, size * 0.075), borderColor: 'transparent', borderTopColor: ink, borderRightColor: ink,
    left: size * 0.33 - r, top: size * 0.67 - r});
  return <View accessible accessibilityRole="image" accessibilityLabel={tagline ? 'Modula Connect. Your number. Your way.' : 'Modula Connect'}
    style={[styles.row, {gap: size * 0.3}]} testID="connect.logo">
    <View style={{width: size, height: size, borderRadius: size * 0.28, backgroundColor: fill, overflow: 'hidden'}}>
      <View style={arc(size * 0.25)}/>
      <View style={arc(size * 0.42)}/>
      <View style={{position: 'absolute', width: size * 0.16, height: size * 0.16, borderRadius: size * 0.08, backgroundColor: ink,
        left: size * 0.33 - size * 0.08, top: size * 0.67 - size * 0.08}}/>
    </View>
    <View>
      <Text allowFontScaling style={{color: theme.colors.text, fontSize: size * 0.5}}>
        Modula <Text style={{fontWeight: '800'}}>Connect</Text></Text>
      {tagline && <ThemedText theme={theme} role="caption" secondary>Your number. Your way.</ThemedText>}
    </View>
  </View>;
}

function UsageMeter({theme, label, used, allowance, unit}: {theme: ModuleTheme; label: string; used: number; allowance: number | null; unit: string}) {
  const fraction = usageFraction(used, allowance);
  const fill = theme.dark ? '#FFFFFF' : '#0B0B0B';
  return <View accessible accessibilityLabel={`${label}: ${used} ${unit}${allowance === null ? ', unlimited' : ` of ${allowance}`}`} style={{gap: 6}}>
    <View style={[styles.row, {justifyContent: 'space-between'}]}>
      <ThemedText theme={theme}>{label}</ThemedText>
      <ThemedText theme={theme} secondary>{allowance === null ? `${used} ${unit} · Unlimited` : `${used} / ${allowance} ${unit}`}</ThemedText>
    </View>
    <View style={{height: 6, borderRadius: 3, backgroundColor: theme.colors.surfaceRaised, overflow: 'hidden'}}>
      <View style={{height: 6, width: `${Math.round(fraction * 100)}%` as `${number}%`, backgroundColor: fill, borderRadius: 3}}/>
    </View>
  </View>;
}

function PreviewBanner({theme}: {theme: ModuleTheme}) {
  return <View accessible accessibilityRole="alert" testID="connect.preview"
    accessibilityLabel="Preview. Modula Connect isn’t live yet. Numbers are illustrative and nothing is charged."
    style={[styles.row, {gap: theme.spacing.xs, padding: theme.spacing.sm, borderRadius: theme.radius.control,
      backgroundColor: theme.colors.warningSurface}]}>
    <Badge theme={theme} label="Preview" tone="warning"/>
    <ThemedText theme={theme} role="caption" style={{flex: 1}}>
      Not live yet. Illustrative numbers only — nothing is provisioned or charged.</ThemedText>
  </View>;
}

const EMPTY_FORM: ComplianceForm = {kind: 'personal', fullName: '', addressLine: '', postcode: '', email: '', mobile: ''};

export function ConnectModule({context, host}: {context: ModuleContext; host: Host; lifecycle: string}) {
  const theme = useMemo(() => moduleTheme(context.environment), [context.environment]);
  const api = useRef<ConnectApi>(createMockConnectApi()).current;
  const alive = useAlive();
  const [stack, setStack] = useState<Step[]>(['welcome']);
  const step = stack[stack.length - 1];
  const [countries, setCountries] = useState<Country[] | null>(null);
  const [country, setCountry] = useState<Country | null>(null);
  const [seed, setSeed] = useState(0);
  const [numbers, setNumbers] = useState<AvailableNumber[] | null>(null);
  const [digits, setDigits] = useState('');
  const [numberType, setNumberType] = useState<NumberType | 'all'>('all');
  const [picked, setPicked] = useState<AvailableNumber | null>(null);
  const [gone, setGone] = useState(false);
  const [plans, setPlans] = useState<Plan[] | null>(null);
  const [plan, setPlan] = useState<Plan | null>(null);
  const [form, setForm] = useState<ComplianceForm>(EMPTY_FORM);
  const [formErrors, setFormErrors] = useState<string[]>([]);
  const [status, setStatus] = useState<VerificationStatus>('notStarted');
  const [busy, setBusy] = useState(false);
  const [terms, setTerms] = useState(false);
  const [simulateFailure, setSimulateFailure] = useState(false);
  const [failed, setFailed] = useState(false);
  const [owned, setOwned] = useState<OwnedNumber[]>([]);
  const [selectedOwned, setSelectedOwned] = useState<OwnedNumber | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [shortlist, setShortlist] = useState<string[]>([]);
  const [memorableOnly, setMemorableOnly] = useState(false);
  const [nickname, setNickname] = useState('');

  const haptic = useCallback(() => { void host.request('haptics.selection').catch(() => {}); }, [host]);
  const push = useCallback((next: Step) => { haptic(); setNotice(null); setStack(s => [...s, next]); }, [haptic]);
  const back = useCallback(() => setStack(s => (s.length > 1 ? s.slice(0, -1) : s)), []);
  const reset = useCallback((to: Step) => setStack([to]), []);

  useEffect(() => { void host.request('diagnostics.dataReady').catch(() => {}); }, [host]);

  const loadNumbers = useCallback(async (nextSeed: number) => {
    setNumbers(null);
    const list = await api.availableNumbers(country?.code ?? 'GB', nextSeed);
    if (alive.current) setNumbers(list);
  }, [api, country, alive]);

  useEffect(() => {
    if (step === 'country' && !countries) void api.countries().then(list => { if (alive.current) setCountries(list); });
    if (step === 'find' && !numbers) void loadNumbers(seed);
    if (step === 'plan' && !plans) void api.plans().then(list => { if (alive.current) setPlans(list); });
    if (step === 'dashboard') void api.numbers().then(list => { if (alive.current) setOwned(list); });
  }, [step, countries, numbers, plans, api, alive, loadNumbers, seed]);

  const choose = useCallback(async (number: AvailableNumber) => {
    setBusy(true);
    const ok = await api.revalidate(number.id);
    if (!alive.current) return;
    setBusy(false);
    if (!ok) { setGone(true); setSeed(s => s + 1); void loadNumbers(seed + 1); return; }
    setGone(false);
    setPicked(number);
    push('details');
  }, [api, alive, loadNumbers, seed, push]);

  const submitVerification = useCallback(async () => {
    const errors = validateCompliance(form);
    setFormErrors(errors);
    if (errors.length) return;
    setBusy(true);
    const next = await api.submitCompliance(form);
    if (!alive.current) return;
    setBusy(false);
    setStatus(next);
    push('status');
  }, [api, alive, form, push]);

  const refreshStatus = useCallback(async () => {
    setBusy(true);
    const next = await api.complianceStatus();
    if (alive.current) { setStatus(next); setBusy(false); }
  }, [api, alive]);

  const activate = useCallback(async () => {
    if (!picked || !plan) return;
    setBusy(true);
    const ok = await api.revalidate(picked.id);
    if (!alive.current) return;
    if (!ok) { setBusy(false); setGone(true); setNumbers(null); reset('find'); return; }
    setFailed(false);
    push('progress');
    try {
      const record = await api.provision(picked.id, plan.id, {simulateFailure});
      if (!alive.current) return;
      setOwned(list => [...list.filter(n => n.id !== record.id), record]);
      setSelectedOwned(record);
      setStack(s => [...s.slice(0, -1), 'activated']);
    } catch {
      if (alive.current) setFailed(true);
    } finally {
      if (alive.current) setBusy(false);
    }
  }, [api, alive, picked, plan, simulateFailure, push, reset]);

  const update = useCallback(async (patch: Partial<OwnedNumber['settings']>) => {
    if (!selectedOwned) return;
    const record = await api.updateSettings(selectedOwned.id, patch);
    if (!alive.current) return;
    setSelectedOwned(record);
    setOwned(list => list.map(n => (n.id === record.id ? record : n)));
  }, [api, alive, selectedOwned]);

  const field = (key: keyof ComplianceForm) => (value: string) => setForm(f => ({...f, [key]: value}));
  const shown = numbers ? filterNumbers(numbers, digits, numberType).filter(n => !memorableOnly || isMemorable(n.display)) : null;
  const toggleShortlist = (id: string) => { haptic(); setShortlist(list => (list.includes(id) ? list.filter(x => x !== id) : [...list, id])); };

  let body: ReactNode;
  switch (step) {
    case 'welcome':
      body = <>
        <View accessible={false} style={[styles.hero, {backgroundColor: theme.colors.surfaceRaised, borderRadius: theme.radius.card * 1.5}]}>
          <ConnectLogo theme={theme} size={56}/>
        </View>
        <ThemedText theme={theme} role="title" accessibilityRole="header">Your number. Your way.</ThemedText>
        <ThemedText theme={theme} secondary>A real phone number, connected to your digital home.</ThemedText>
        <ThemedText theme={theme} role="caption" secondary>
          A cloud number inside Modula — not a SIM or eSIM, and not a replacement for your mobile service. It can’t be used for emergency calls (999/112).
        </ThemedText>
        <Action theme={theme} title="Get Started" onPress={() => push('connection')} testID="connect.start"/>
        {owned.length > 0 && <Action theme={theme} title="My numbers" secondary onPress={() => push('dashboard')}/>}
      </>;
      break;
    case 'connection':
      body = <>
        <Choice theme={theme} title="Get a new Modula Number" subtitle="Pick a UK (+44) number that lives in Modula." onPress={() => push('country')} testID="connect.new"/>
        <Choice theme={theme} title="Connect my existing number" subtitle="Verify your SIM number so friends can find you. It stays with your carrier." onPress={() => setNotice('Verifying an existing number is coming soon in this preview.')}/>
        <Choice theme={theme} title="Transfer a number" subtitle="Move a number to Modula." disabled trailing={<Badge theme={theme} label="Coming soon"/>}/>
      </>;
      break;
    case 'country':
      body = !countries ? <LoadingRow theme={theme} label="Loading countries"/> : <>
        {countries.map(c => <Choice key={c.code} theme={theme} title={`${c.flag}  ${c.name}`} subtitle={c.available ? c.dialCode : `${c.dialCode} · coming later`}
          disabled={!c.available} selected={country?.code === c.code}
          onPress={() => { setCountry(c); setNumbers(null); push('find'); }}/>)}
      </>;
      break;
    case 'find':
      body = <>
        {gone && <InlineNotice theme={theme} message="This number is no longer available. Here are some fresh alternatives."/>}
        <SearchField theme={theme} value={digits} onChangeText={value => setDigits(value.replace(/[^\d ]/g, ''))} placeholder="Search digits, e.g. 123" label="Search numbers by digits"/>
        <SegmentedControl theme={theme} label="Number type" value={numberType} onChange={setNumberType}
          options={(['all', 'mobile', 'local', 'tollFree'] as const).map(v => ({value: v, label: typeLabel(v)}))}/>
        <Action theme={theme} title="Refresh numbers" secondary onPress={() => { setGone(false); setSeed(s => s + 1); void loadNumbers(seed + 1); }}/>
        <ToggleRow theme={theme} label="Memorable numbers only" value={memorableOnly} onChange={setMemorableOnly} testID="connect.memorable"/>
        {shortlist.length > 0 && <ThemedText theme={theme} role="caption" secondary>{`Shortlisted: ${shortlist.length}. Tap ☆ to keep a number in view while you compare.`}</ThemedText>}
        {!shown ? <LoadingRow theme={theme} label="Finding numbers"/> : shown.length === 0
          ? <ThemedText theme={theme} secondary>No numbers match. Try other digits or refresh.</ThemedText>
          : shown.map(n => <Choice key={n.id} theme={theme} title={n.display} subtitle={`${typeLabel(n.type)}${n.locality ? ` · ${n.locality}` : ''} · ${n.capabilities.map(capabilityLabel).join(' + ')}`}
              disabled={busy} onPress={() => void choose(n)} selected={shortlist.includes(n.id)}
              trailing={<View style={[styles.row, {gap: 8}]}>
                {isMemorable(n.display) && <Badge theme={theme} label="Memorable"/>}
                <Badge theme={theme} label="Illustrative"/>
                <Pressable accessibilityRole="button" accessibilityLabel={shortlist.includes(n.id) ? `Remove ${n.display} from shortlist` : `Shortlist ${n.display}`}
                  hitSlop={10} onPress={() => toggleShortlist(n.id)}>
                  <Text style={{color: theme.colors.text, fontSize: 20}}>{shortlist.includes(n.id) ? '★' : '☆'}</Text>
                </Pressable>
              </View>}/>)}
      </>;
      break;
    case 'details':
      body = picked && <>
        <ModuleCard theme={theme}>
          <ThemedText theme={theme} role="largeTitle">{picked.display}</ThemedText>
          <Badge theme={theme} label="Illustrative number"/>
        </ModuleCard>
        <KeyValueList theme={theme} items={[
          {label: 'Type', value: typeLabel(picked.type)},
          {label: 'Works with', value: picked.capabilities.map(capabilityLabel).join(', ')},
          {label: 'Number fee', value: formatPrice(picked.monthlyPence)},
          {label: 'Country', value: `${country?.flag ?? '🇬🇧'} ${country?.name ?? 'United Kingdom'}`},
        ]}/>
        <Action theme={theme} title="Select this number" onPress={() => push('plan')}/>
      </>;
      break;
    case 'plan':
      body = !plans ? <LoadingRow theme={theme} label="Loading plans"/> : <>
        <ThemedText theme={theme} role="caption" secondary>Proposed plans — prices aren’t final.</ThemedText>
        {plans.map(p => <Choice key={p.id} theme={theme} title={`${p.name} · ${formatPrice(p.monthlyPence, p.fromPrice)}`}
          subtitle={`${p.allowances.join(' · ')}\nExtra usage: ${p.extraUsage}`} selected={plan?.id === p.id}
          disabled={!p.publicNumber} onPress={() => setPlan(p)}
          trailing={!p.publicNumber ? <Badge theme={theme} label="No number"/> : undefined}/>)}
        <Action theme={theme} title="Continue" disabled={!plan} onPress={() => push(status === 'approved' ? 'review' : 'verify')}/>
      </>;
      break;
    case 'verify':
      body = <>
        <ThemedText theme={theme} secondary>UK numbers need an identity check (regulatory bundle): ID, address, contact details and a reachable mobile.</ThemedText>
        <SegmentedControl theme={theme} label="Account type" value={form.kind} onChange={(kind: IdentityKind) => setForm(f => ({...f, kind}))}
          options={[{value: 'personal', label: 'Personal'}, {value: 'business', label: 'Business'}]}/>
        {form.kind === 'business' && <FormField theme={theme} label="Business name" value={form.businessName ?? ''} onChangeText={field('businessName')}/>}
        <FormField theme={theme} label="Full legal name" value={form.fullName} onChangeText={field('fullName')}/>
        <FormField theme={theme} label="UK address" value={form.addressLine} onChangeText={field('addressLine')}/>
        <FormField theme={theme} label="Postcode" value={form.postcode} onChangeText={field('postcode')}/>
        <FormField theme={theme} label="Contact email" value={form.email} onChangeText={field('email')} keyboardType="email-address"/>
        <FormField theme={theme} label="Reachable mobile" value={form.mobile} onChangeText={field('mobile')} keyboardType="numeric" hint="We’d text a code here (not in the preview)."/>
        <Choice theme={theme} title={form.documentName ? `Document: ${form.documentName}` : 'Add proof of identity'}
          subtitle="Passport or driving licence. Preview: nothing is uploaded." selected={Boolean(form.documentName)}
          onPress={() => setForm(f => ({...f, documentName: f.documentName ? undefined : 'identity-preview.jpg'}))}/>
        {formErrors.length > 0 && <InlineNotice theme={theme} tone="danger" message={formErrors.join('\n')}/>}
        <Action theme={theme} title={busy ? 'Submitting…' : 'Submit for review'} disabled={busy} onPress={() => void submitVerification()}/>
      </>;
      break;
    case 'status': {
      const copy: Record<VerificationStatus, [string, string]> = {
        notStarted: ['Not started', 'Add your details to continue.'],
        underReview: ['Under review', 'We’re checking your details. This usually takes a few minutes in the preview.'],
        approved: ['Approved', 'You’re verified. Review your number and plan next.'],
        moreInfo: ['More info needed', 'Some details were missing. Update them and resubmit.'],
        rejected: ['Not approved', 'We couldn’t verify these details. Contact support to appeal.'],
      };
      body = <>
        <ModuleCard theme={theme}>
          <ThemedText theme={theme} role="title" accessibilityRole="header">{copy[status][0]}</ThemedText>
          <ThemedText theme={theme} secondary>{copy[status][1]}</ThemedText>
        </ModuleCard>
        {status === 'underReview' && <Action theme={theme} title={busy ? 'Checking…' : 'Check status'} disabled={busy} onPress={() => void refreshStatus()}/>}
        {status === 'approved' && <Action theme={theme} title="Continue" onPress={() => push('review')}/>}
        {(status === 'moreInfo' || status === 'rejected') && <Action theme={theme} title="Update details" onPress={back}/>}
      </>;
      break;
    }
    case 'review':
      body = picked && plan && <>
        <KeyValueList theme={theme} items={[
          {label: 'Number', value: `${picked.display} (illustrative)`},
          {label: 'Plan', value: plan.name},
          {label: 'You’d pay', value: `${recurringTotal(plan, picked)}, renews monthly`},
          {label: 'Payment', value: 'Not charged in the preview'},
        ]}/>
        <ThemedText theme={theme} role="caption" secondary>
          The full recurring price is always shown before activation. In-app payment needs App Store review and isn’t live. Not for emergency calls.
        </ThemedText>
        <ToggleRow theme={theme} label="I agree to the Modula Connect terms (draft)" value={terms} onChange={setTerms}/>
        <ToggleRow theme={theme} label="Preview: simulate an activation failure" value={simulateFailure} onChange={setSimulateFailure}/>
        <Action theme={theme} title="Confirm (preview)" disabled={!terms || busy} onPress={() => void activate()} testID="connect.confirm"/>
      </>;
      break;
    case 'progress':
      body = failed ? <>
        <InlineNotice theme={theme} tone="danger" message="Activation didn’t finish. Nothing was charged."/>
        <Action theme={theme} title="Try again" onPress={() => { setSimulateFailure(false); back(); }}/>
        <Action theme={theme} title="Choose another number" secondary onPress={() => { setNumbers(null); reset('find'); }}/>
      </> : <>
        <LoadingRow theme={theme} label="Setting up your number (preview)…"/>
        <ThemedText theme={theme} secondary>Reserving · Verifying · Connecting — this is simulated; no carrier is contacted.</ThemedText>
      </>;
      break;
    case 'activated':
      body = selectedOwned && <>
        <ModuleCard theme={theme}>
          <Badge theme={theme} label="Preview — not really active"/>
          <ThemedText theme={theme} role="largeTitle">{selectedOwned.number.display}</ThemedText>
          <ThemedText theme={theme} secondary>This is what you’ll see once Connect is live. The number isn’t provisioned and can’t make or take calls yet.</ThemedText>
        </ModuleCard>
        <Action theme={theme} title="Share number" secondary onPress={() => void Share.share({message: `${selectedOwned.number.display} (Modula Connect preview — illustrative number)`}).catch(() => {})}/>
        <ToggleRow theme={theme} label="Notify me for texts and calls" value={selectedOwned.settings.smsNotifications}
          onChange={value => void update({smsNotifications: value, callNotifications: value})}/>
        <Action theme={theme} title="Continue" onPress={() => reset('dashboard')}/>
      </>;
      break;
    case 'dashboard': {
      const first = owned[0];
      const usage = first ? mockUsage(first.id, plans?.find(p => p.id === first.planID)) : null;
      body = <>
        <ConnectLogo theme={theme} size={36} tagline/>
        {first && usage && <ModuleCard theme={theme}>
          <ThemedText theme={theme} role="headline">{first.settings.nickname || 'This month'}</ThemedText>
          <UsageMeter theme={theme} label="Texts" used={usage.texts} allowance={usage.textsAllowance} unit="texts"/>
          <UsageMeter theme={theme} label="Minutes" used={usage.minutes} allowance={usage.minutesAllowance} unit="min"/>
          <ThemedText theme={theme} role="caption" secondary>Illustrative usage. No real texts or calls happen in the preview.</ThemedText>
        </ModuleCard>}
        {owned.length === 0 ? <ThemedText theme={theme} secondary>No numbers yet.</ThemedText> : owned.map(n =>
          <Choice key={n.id} theme={theme} title={n.number.display} subtitle={`${lifecycleLabel(n.state)} · ${plans?.find(p => p.id === n.planID)?.name ?? n.planID}`}
            onPress={() => { setSelectedOwned(n); setNickname(''); push('settings'); }} trailing={<Badge theme={theme} label="Preview"/>}/>)}
        <Section theme={theme} title="Your number" footer="Messages and Calls are foundations only. Live texts and calls arrive after backend certification.">
          {['Messages', 'Calls', 'Contacts', 'Voicemail'].map(label =>
            <Choice key={label} theme={theme} title={label} disabled trailing={<Badge theme={theme} label={label === 'Voicemail' ? 'Later' : 'Coming soon'}/>}/>)}
        </Section>
        <Action theme={theme} title="Get another number" secondary onPress={() => reset('connection')}/>
      </>;
      break;
    }
    case 'settings':
      body = selectedOwned && <>
        <KeyValueList theme={theme} items={[
          {label: 'Number', value: selectedOwned.number.display},
          {label: 'Status', value: lifecycleLabel(selectedOwned.state)},
        ]}/>
        <ToggleRow theme={theme} label="Text notifications" value={selectedOwned.settings.smsNotifications} onChange={v => void update({smsNotifications: v})}/>
        <ToggleRow theme={theme} label="Call notifications" value={selectedOwned.settings.callNotifications} onChange={v => void update({callNotifications: v})}/>
        <FormField theme={theme} label="Nickname (only you see it)" value={nickname || selectedOwned.settings.nickname}
          onChangeText={value => setNickname(value.slice(0, 40))}/>
        <Action theme={theme} title="Save nickname" secondary disabled={!nickname || nickname === selectedOwned.settings.nickname}
          onPress={() => { void update({nickname: nickname.trim()}); setNotice('Nickname saved.'); }}/>
        <ToggleRow theme={theme} label="Filter likely spam" value={selectedOwned.settings.spamFilter} onChange={v => void update({spamFilter: v})}/>
        <ToggleRow theme={theme} label="Quiet hours (22:00–07:00)" value={selectedOwned.settings.quietHours} onChange={v => void update({quietHours: v})}/>
        {selectedOwned.planID === 'business' && <ToggleRow theme={theme} label="Business hours only (Mon–Fri 09:00–17:30)"
          value={selectedOwned.settings.businessHours} onChange={v => void update({businessHours: v})}/>}
        <Section theme={theme} title="Status timeline" footer="Simulated in the preview. No carrier is contacted.">
          {LIFECYCLE_ORDER.map((state, i) => {
            const reached = i <= lifecycleProgress(selectedOwned.state);
            return <View key={state} accessible accessibilityLabel={`${lifecycleLabel(state)}${reached ? ', done' : ''}`}
              style={[styles.row, {gap: 10, minHeight: 32}]}>
              <Text style={{color: theme.colors.text, fontSize: 16, width: 20, textAlign: 'center'}}>{reached ? '●' : '○'}</Text>
              <ThemedText theme={theme} secondary={!reached}>{lifecycleLabel(state)}</ThemedText>
            </View>;
          })}
        </Section>
        <Action theme={theme} title="Share number" secondary onPress={() => void Share.share({message: `${selectedOwned.number.display} (Modula Connect preview — illustrative number)`}).catch(() => {})}/>
        <ToggleRow theme={theme} label="Voicemail (later)" value={selectedOwned.settings.voicemail} disabled onChange={() => {}}/>
        <ToggleRow theme={theme} label="Call forwarding (later)" value={selectedOwned.settings.forwarding} disabled onChange={() => {}}/>
        {selectedOwned.state === 'active' && <Action theme={theme} title="Cancel number" secondary onPress={() => void api.cancel(selectedOwned.id).then(record => {
          if (!alive.current) return;
          setSelectedOwned(record);
          setOwned(list => list.map(n => (n.id === record.id ? record : n)));
        })}/>}
      </>;
      break;
  }

  return <View style={{flex: 1, backgroundColor: theme.colors.canvas}} testID={`connect.${step}`}>
    <View style={[styles.row, {paddingHorizontal: theme.spacing.lg, paddingTop: theme.spacing.sm, gap: theme.spacing.sm, minHeight: theme.minimumTouchTarget}]}>
      {stack.length > 1 && step !== 'progress' && <Pressable accessibilityRole="button" accessibilityLabel="Back" onPress={back} hitSlop={8}
        style={[styles.back, {backgroundColor: theme.colors.surfaceRaised}]}>
        <Text style={{color: theme.colors.text, fontSize: 18, fontWeight: '600'}}>‹</Text>
      </Pressable>}
      <ThemedText theme={theme} role="headline" accessibilityRole="header" style={{flex: 1}}>{STEP_TITLES[step]}</ThemedText>
    </View>
    <ScrollView contentContainerStyle={{padding: theme.spacing.lg, gap: theme.spacing.md}} keyboardShouldPersistTaps="handled">
      <PreviewBanner theme={theme}/>
      {notice && <InlineNotice theme={theme} tone="neutral" message={notice}/>}
      {body}
    </ScrollView>
  </View>;
}

const styles = StyleSheet.create({
  row: {flexDirection: 'row', alignItems: 'center'},
  action: {alignItems: 'center', justifyContent: 'center', paddingHorizontal: 20},
  choice: {borderStyle: 'solid'},
  hero: {height: 160, alignItems: 'center', justifyContent: 'center'},
  back: {width: 36, height: 36, borderRadius: 18, alignItems: 'center', justifyContent: 'center'},
});
