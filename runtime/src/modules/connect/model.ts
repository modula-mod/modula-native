/**
 * Modula Connect (spec v1.0, t221u) — frontend model on MOCK data.
 *
 * Nothing here talks to Twilio/Telnyx or the network. `ConnectApi` mirrors the planned GreenField
 * contracts (/api/connect/*, not live yet) so a real client can replace `mockConnectApi` later.
 * Mock numbers are fictional Ofcom drama-range numbers (07700 900xxx) and are always labelled
 * illustrative. Nothing is charged and no number is ever shown as activated for real.
 */

export type Country = {code: string; name: string; flag: string; dialCode: string; available: boolean};
export type NumberType = 'mobile' | 'local' | 'tollFree';
export type Capability = 'sms' | 'voice' | 'mms';
export type AvailableNumber = {
  id: string; e164: string; display: string; type: NumberType; locality?: string;
  capabilities: Capability[]; monthlyPence: number; illustrative: true;
};
export type Plan = {
  id: string; name: string; monthlyPence: number | null; fromPrice?: boolean; publicNumber: boolean;
  allowances: string[]; extraUsage: string; proposal: true;
};
export type IdentityKind = 'personal' | 'business';
export type ComplianceForm = {
  kind: IdentityKind; fullName: string; addressLine: string; postcode: string; email: string; mobile: string;
  businessName?: string; documentName?: string;
};
export type VerificationStatus = 'notStarted' | 'underReview' | 'approved' | 'moreInfo' | 'rejected';
export type LifecycleState =
  | 'available' | 'verificationPending' | 'readyToProvision' | 'provisioning' | 'active'
  | 'verificationRejected' | 'numberUnavailable' | 'paymentFailed' | 'provisioningFailed' | 'suspended' | 'cancellationPending';
export type OwnedNumber = {
  id: string; number: AvailableNumber; planID: string; state: LifecycleState;
  settings: {smsNotifications: boolean; callNotifications: boolean; voicemail: boolean; forwarding: boolean;
    spamFilter: boolean; quietHours: boolean; businessHours: boolean; nickname: string;
    forwardMode?: ForwardMode; forwardTo?: string; voicemailGreeting?: 'default' | 'custom'; voicemailText?: string};
};

export const LIFECYCLE_ORDER: LifecycleState[] = ['available', 'verificationPending', 'readyToProvision', 'provisioning', 'active'];
export const RECOVERY_STATES: LifecycleState[] = ['verificationRejected', 'numberUnavailable', 'paymentFailed', 'provisioningFailed', 'suspended', 'cancellationPending'];

const ALLOWED: Record<LifecycleState, LifecycleState[]> = {
  available: ['verificationPending', 'numberUnavailable'],
  verificationPending: ['readyToProvision', 'verificationRejected'],
  readyToProvision: ['provisioning', 'paymentFailed', 'numberUnavailable'],
  provisioning: ['active', 'provisioningFailed'],
  active: ['suspended', 'cancellationPending'],
  verificationRejected: ['verificationPending'],
  numberUnavailable: ['available'],
  paymentFailed: ['readyToProvision'],
  provisioningFailed: ['provisioning', 'readyToProvision'],
  suspended: ['active', 'cancellationPending'],
  cancellationPending: ['active'],
};

export function canTransition(from: LifecycleState, to: LifecycleState): boolean {
  return ALLOWED[from].includes(to);
}

export function transition(number: OwnedNumber, to: LifecycleState): OwnedNumber {
  if (!canTransition(number.state, to)) throw new Error(`Invalid Connect transition ${number.state} → ${to}`);
  return {...number, state: to};
}

export function lifecycleLabel(state: LifecycleState): string {
  switch (state) {
    case 'available': return 'Available';
    case 'verificationPending': return 'Verification pending';
    case 'readyToProvision': return 'Ready to activate';
    case 'provisioning': return 'Activating';
    case 'active': return 'Active (preview)';
    case 'verificationRejected': return 'Verification not approved';
    case 'numberUnavailable': return 'Number no longer available';
    case 'paymentFailed': return 'Payment failed';
    case 'provisioningFailed': return 'Activation failed';
    case 'suspended': return 'Suspended';
    case 'cancellationPending': return 'Cancellation pending';
  }
}

export function formatPrice(pence: number | null, fromPrice = false): string {
  if (pence === null || pence === 0) return 'Free';
  return `${fromPrice ? 'from ' : ''}£${(pence / 100).toFixed(2)}/month`;
}

/** Only fictional 07700 900000–900999 numbers are ever produced. */
export function isIllustrativeNumber(e164: string): boolean {
  return /^\+447700900\d{3}$/.test(e164);
}

export function displayUK(e164: string): string {
  const national = '0' + e164.slice(3);
  return `${national.slice(0, 5)} ${national.slice(5)}`;
}

export function validateCompliance(form: ComplianceForm): string[] {
  const errors: string[] = [];
  if (form.fullName.trim().length < 2) errors.push('Enter your full legal name.');
  if (form.addressLine.trim().length < 5) errors.push('Enter your UK address.');
  if (!/^[A-Z]{1,2}\d[A-Z\d]? ?\d[A-Z]{2}$/i.test(form.postcode.trim())) errors.push('Enter a valid UK postcode.');
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(form.email.trim())) errors.push('Enter a contact email.');
  if (!/^(\+44|0)7\d{9}$/.test(form.mobile.replace(/\s/g, ''))) errors.push('Enter a reachable UK mobile number.');
  if (form.kind === 'business' && !(form.businessName ?? '').trim()) errors.push('Enter the business name.');
  if (!form.documentName) errors.push('Add a proof of identity document.');
  return errors;
}

export function filterNumbers(numbers: AvailableNumber[], digits: string, type: NumberType | 'all'): AvailableNumber[] {
  const needle = digits.replace(/\D/g, '');
  return numbers.filter(n => (type === 'all' || n.type === type) && (!needle || n.e164.replace(/\D/g, '').includes(needle)));
}

// MARK: - Mock API (mirrors planned /api/connect/* contracts)

export type ConnectApi = {
  countries(): Promise<Country[]>;
  availableNumbers(country: string, seed: number): Promise<AvailableNumber[]>;
  plans(): Promise<Plan[]>;
  submitCompliance(form: ComplianceForm): Promise<VerificationStatus>;
  complianceStatus(): Promise<VerificationStatus>;
  /** Inventory revalidation right before review/activation (backend owns the real check). */
  revalidate(numberID: string): Promise<boolean>;
  provision(numberID: string, planID: string, options?: {simulateFailure?: boolean}): Promise<OwnedNumber>;
  numbers(): Promise<OwnedNumber[]>;
  updateSettings(id: string, settings: Partial<OwnedNumber['settings']>): Promise<OwnedNumber>;
  cancel(id: string): Promise<OwnedNumber>;
};

/** Mock inventory: the 6th number of every batch is "taken" by the time you pick it (demo of the gone state). */
export function isMockTaken(numberID: string): boolean {
  return /-5$/.test(numberID);
}

export type Step =
  | 'welcome' | 'connection' | 'country' | 'find' | 'details' | 'plan' | 'verify' | 'status'
  | 'review' | 'progress' | 'activated' | 'dashboard' | 'settings'
  | 'transfer' | 'transferStatus' | 'forwarding' | 'voicemail' | 'compare';

export const STEP_TITLES: Record<Step, string> = {
  welcome: 'Modula Connect', connection: 'Choose connection', country: 'Choose country', find: 'Find your number',
  details: 'Number details', plan: 'Your number plan', verify: 'Verify identity', status: 'Verification status',
  review: 'Review & activate', progress: 'Activating', activated: 'Number ready', dashboard: 'My numbers', settings: 'Number settings',
  transfer: 'Transfer a number', transferStatus: 'Transfer status', forwarding: 'Call forwarding', voicemail: 'Voicemail',
  compare: 'Compare plans',
};

// MARK: Preview extras (5:00 round) — all mock, nothing contacts a carrier.

export type ForwardMode = 'off' | 'always' | 'busy' | 'noAnswer';

export function forwardModeLabel(mode: ForwardMode): string {
  return mode === 'off' ? 'Off' : mode === 'always' ? 'Always' : mode === 'busy' ? 'When busy' : 'No answer';
}

/** UK mobile or landline for forwarding: 07… / 01… / 02… or +44 equivalent, 10–11 digits. */
export function validateForwardTarget(raw: string): string | null {
  const compact = raw.replace(/[\s()-]/g, '');
  const national = compact.startsWith('+44') ? `0${compact.slice(3)}` : compact;
  if (!/^0[127]\d{8,9}$/.test(national)) return 'Enter a UK number starting 07, 01 or 02.';
  if (/^0(9|8)/.test(national)) return 'Premium and special-rate numbers can’t be used.';
  return null;
}

/** UK switching codes: PAC (3 letters + 6 digits) keeps the number; STAC (6 digits + 3 letters) doesn’t. */
export function classifySwitchCode(raw: string): 'pac' | 'stac' | null {
  const code = raw.replace(/\s/g, '').toUpperCase();
  if (/^[A-Z]{3}\d{6}$/.test(code)) return 'pac';
  if (/^\d{6}[A-Z]{3}$/.test(code)) return 'stac';
  return null;
}

export type TransferForm = {number: string; provider: string; code: string; accountHolder: string};

export function validateTransfer(form: TransferForm): string[] {
  const errors: string[] = [];
  const digits = form.number.replace(/\D/g, '');
  if (!/^(07\d{9}|447\d{9})$/.test(digits)) errors.push('Enter the UK mobile number you want to move.');
  if (!form.provider.trim()) errors.push('Choose your current provider.');
  const kind = classifySwitchCode(form.code);
  if (kind === null) errors.push('Enter a PAC code like ABC123456 (text PAC to 65075 to get one).');
  if (kind === 'stac') errors.push('That’s a STAC — it cancels without keeping the number. Text PAC to 65075 instead.');
  if (!form.accountHolder.trim()) errors.push('Enter the account holder’s name.');
  return errors;
}

export const TRANSFER_STEPS = ['Request received', 'Code checked with your provider', 'Switch day booked', 'Number moves to Modula'] as const;

/** Next working day after `from` (UK switches complete within one working day of a valid PAC). */
export function nextWorkingDay(from: Date): Date {
  const d = new Date(from.getTime());
  do { d.setDate(d.getDate() + 1); } while (d.getDay() === 0 || d.getDay() === 6);
  return d;
}

export type MockVoicemail = {id: string; from: string; ago: string; seconds: number; transcript: string; illustrative: true};

export function mockVoicemails(numberID: string): MockVoicemail[] {
  const base = numberID.length;
  return [
    {id: `${numberID}-vm1`, from: '07700 900461', ago: '12 min ago', seconds: 18 + (base % 5), illustrative: true,
      transcript: 'Hi, it’s Sam — just checking you got the parcel. Call me back when you can.'},
    {id: `${numberID}-vm2`, from: '07700 900118', ago: 'Yesterday', seconds: 9, illustrative: true,
      transcript: 'Your table for two at 7 is confirmed. See you then.'},
    {id: `${numberID}-vm3`, from: 'Unknown', ago: 'Mon', seconds: 31, illustrative: true,
      transcript: 'This is a reminder about your appointment on Thursday at 10:30.'},
  ];
}

/** Rows for the plan comparison grid (value per plan id; true/false render as ✓/–). */
export const PLAN_COMPARISON: {label: string; values: Record<string, string | boolean>}[] = [
  {label: 'Public UK number', values: {core: false, personal: true, plus: true, business: true}},
  {label: 'Modula-to-Modula calls', values: {core: true, personal: true, plus: true, business: true}},
  {label: 'SMS and calls', values: {core: false, personal: 'Allowance', plus: 'Bigger', business: 'Custom'}},
  {label: 'Voicemail', values: {core: false, personal: 'Later', plus: 'Later', business: 'Later'}},
  {label: 'Call forwarding', values: {core: false, personal: false, plus: 'Later', business: 'Later'}},
  {label: 'Team routing', values: {core: false, personal: false, plus: false, business: 'Later'}},
];

export function capabilityLabel(capability: Capability): string {
  return capability === 'sms' ? 'SMS' : capability === 'mms' ? 'MMS' : 'Voice';
}

export function typeLabel(type: NumberType | 'all'): string {
  return type === 'all' ? 'All' : type === 'mobile' ? 'Mobile' : type === 'local' ? 'Local' : 'Free-phone';
}

/** Full recurring price line shown before activation (plan + any number fee). */
export function recurringTotal(plan: Plan, number: AvailableNumber): string {
  if (plan.monthlyPence === null && number.monthlyPence === 0) return 'Free';
  const pence = (plan.monthlyPence ?? 0) + number.monthlyPence;
  return formatPrice(pence, plan.fromPrice);
}

const wait = (ms: number) => new Promise<void>(resolve => setTimeout(resolve, ms));

export function mockNumbers(seed: number): AvailableNumber[] {
  const types: NumberType[] = ['mobile', 'mobile', 'local', 'mobile', 'tollFree', 'mobile'];
  return Array.from({length: 8}, (_, i) => {
    const suffix = String((seed * 137 + i * 211) % 1000).padStart(3, '0');
    const e164 = `+447700900${suffix}`;
    const type = types[i % types.length];
    return {
      id: `mock-${seed}-${i}`, e164, display: displayUK(e164), type,
      locality: type === 'local' ? 'London (illustrative)' : undefined,
      capabilities: type === 'tollFree' ? ['voice'] : ['sms', 'voice'],
      monthlyPence: type === 'tollFree' ? 1299 : 0,
      illustrative: true,
    };
  });
}

/** Plan proposals as the config endpoint would return them (not final pricing). */
export const MOCK_PLAN_CONFIG: Plan[] = [
  {id: 'core', name: 'Modula Core', monthlyPence: null, publicNumber: false, allowances: ['Modula-to-Modula calls and messages', 'No public number'], extraUsage: 'None', proposal: true},
  {id: 'personal', name: 'Personal Number', monthlyPence: 699, publicNumber: true, allowances: ['1 UK number', 'SMS and calls (allowance TBC)', 'Voicemail later'], extraUsage: 'Pay as you go, shown before use', proposal: true},
  {id: 'plus', name: 'Connect Plus', monthlyPence: 999, publicNumber: true, allowances: ['Everything in Personal', 'Bigger allowances', 'Call forwarding later'], extraUsage: 'Lower extra-usage rates', proposal: true},
  {id: 'business', name: 'Connect Business', monthlyPence: 1999, fromPrice: true, publicNumber: true, allowances: ['Business verification', 'Team routing later'], extraUsage: 'Custom', proposal: true},
];

export function createMockConnectApi(latencyMs = 450): ConnectApi {
  let status: VerificationStatus = 'notStarted';
  const owned: OwnedNumber[] = [];
  return {
    async countries() {
      await wait(latencyMs);
      return [
        {code: 'GB', name: 'United Kingdom', flag: '🇬🇧', dialCode: '+44', available: true},
        {code: 'IE', name: 'Ireland', flag: '🇮🇪', dialCode: '+353', available: false},
        {code: 'US', name: 'United States', flag: '🇺🇸', dialCode: '+1', available: false},
      ];
    },
    async availableNumbers(_country, seed) { await wait(latencyMs); return mockNumbers(seed); },
    async plans() { await wait(latencyMs); return MOCK_PLAN_CONFIG; },
    async submitCompliance(form) {
      await wait(latencyMs);
      status = validateCompliance(form).length ? 'moreInfo' : 'underReview';
      return status;
    },
    async complianceStatus() {
      await wait(latencyMs);
      // Mock reviewer: an under-review bundle is approved on the next check.
      if (status === 'underReview') status = 'approved';
      return status;
    },
    async revalidate(numberID) { await wait(latencyMs); return !isMockTaken(numberID); },
    async provision(numberID, planID, options) {
      await wait(latencyMs * 3);
      if (options?.simulateFailure) throw new Error('provisioningFailed');
      const number = mockNumbers(0).concat(mockNumbers(1), mockNumbers(2)).find(n => n.id === numberID) ?? mockNumbers(0)[0];
      const record: OwnedNumber = {id: `owned-${numberID}`, number, planID, state: 'active',
        settings: {...DEFAULT_NUMBER_SETTINGS}};
      owned.push(record);
      return record;
    },
    async numbers() { await wait(latencyMs); return [...owned]; },
    async updateSettings(id, settings) {
      await wait(latencyMs / 3);
      const index = owned.findIndex(n => n.id === id);
      if (index < 0) throw new Error('notFound');
      owned[index] = {...owned[index], settings: {...owned[index].settings, ...settings}};
      return owned[index];
    },
    async cancel(id) {
      await wait(latencyMs);
      const index = owned.findIndex(n => n.id === id);
      if (index < 0) throw new Error('notFound');
      owned[index] = transition(owned[index], 'cancellationPending');
      return owned[index];
    },
  };
}


// MARK: t237u — more Connect features (mock/local only)

export const DEFAULT_NUMBER_SETTINGS: OwnedNumber['settings'] = {
  smsNotifications: true, callNotifications: true, voicemail: false, forwarding: false,
  spamFilter: true, quietHours: false, businessHours: false, nickname: '',
};

/** A number is "memorable" when its last six digits repeat a digit 3+ times or form a run. */
export function isMemorable(display: string): boolean {
  const digits = display.replace(/\D/g, '').slice(-6);
  if (digits.length < 6) return false;
  const counts = new Map<string, number>();
  for (const d of digits) counts.set(d, (counts.get(d) ?? 0) + 1);
  if ([...counts.values()].some(c => c >= 3)) return true;
  let run = 1;
  for (let i = 1; i < digits.length; i++) {
    const step = Number(digits[i]) - Number(digits[i - 1]);
    run = step === 1 ? run + 1 : 1;
    if (run >= 4) return true;
  }
  return /(\d\d)\1/.test(digits);
}

export type UsageSnapshot = {texts: number; textsAllowance: number | null; minutes: number; minutesAllowance: number | null; illustrative: true};

/** Deterministic, clearly illustrative usage for the dashboard meter (no real traffic exists). */
export function mockUsage(numberID: string, plan?: Plan | null): UsageSnapshot {
  let h = 0;
  for (const c of numberID) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  const textsAllowance = plan?.id === 'business' ? null : plan?.id === 'plus' ? 1000 : 250;
  const minutesAllowance = plan?.id === 'business' ? null : plan?.id === 'plus' ? 500 : 100;
  return {texts: h % 120, textsAllowance, minutes: (h >> 8) % 60, minutesAllowance, illustrative: true};
}

export function usageFraction(used: number, allowance: number | null): number {
  if (allowance === null || allowance <= 0) return 0;
  return Math.max(0, Math.min(1, used / allowance));
}

/** Progress through the activation lifecycle, for the settings timeline. */
export function lifecycleProgress(state: LifecycleState): number {
  const i = LIFECYCLE_ORDER.indexOf(state);
  return i < 0 ? -1 : i;
}
