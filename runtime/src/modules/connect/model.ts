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
  settings: {smsNotifications: boolean; callNotifications: boolean; voicemail: boolean; forwarding: boolean};
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
  | 'review' | 'progress' | 'activated' | 'dashboard' | 'settings';

export const STEP_TITLES: Record<Step, string> = {
  welcome: 'Modula Connect', connection: 'Choose connection', country: 'Choose country', find: 'Find your number',
  details: 'Number details', plan: 'Your number plan', verify: 'Verify identity', status: 'Verification status',
  review: 'Review & activate', progress: 'Activating', activated: 'Number ready', dashboard: 'My numbers', settings: 'Number settings',
};

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
        settings: {smsNotifications: true, callNotifications: true, voicemail: false, forwarding: false}};
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
