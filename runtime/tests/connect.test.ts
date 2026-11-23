import {test} from 'node:test';
import assert from 'node:assert/strict';
import {canTransition, createMockConnectApi, recurringTotal, displayUK, filterNumbers, formatPrice, isIllustrativeNumber, mockNumbers, transition, validateCompliance,
  MOCK_PLAN_CONFIG, type OwnedNumber} from '../src/modules/connect/model';

test('mock numbers are only fictional 07700 900xxx', () => {
  for (let seed = 0; seed < 20; seed++) {
    for (const n of mockNumbers(seed)) {
      assert.ok(isIllustrativeNumber(n.e164), n.e164);
      assert.equal(n.illustrative, true);
      assert.match(n.display, /^07700 900\d{3}$/);
    }
  }
});

test('lifecycle only allows the documented transitions', () => {
  assert.ok(canTransition('available', 'verificationPending'));
  assert.ok(canTransition('provisioning', 'active'));
  assert.ok(!canTransition('available', 'active'));
  const base: OwnedNumber = {id: 'x', number: mockNumbers(0)[0], planID: 'personal', state: 'available',
    settings: {smsNotifications: true, callNotifications: true, voicemail: false, forwarding: false}};
  assert.throws(() => transition(base, 'active'));
  assert.equal(transition(base, 'verificationPending').state, 'verificationPending');
});

test('pricing and formatting', () => {
  assert.equal(formatPrice(null), 'Free');
  assert.equal(formatPrice(699), '£6.99/month');
  assert.equal(formatPrice(1999, true), 'from £19.99/month');
  assert.equal(displayUK('+447700900123'), '07700 900123');
  assert.ok(MOCK_PLAN_CONFIG.every(p => p.proposal));
});

test('compliance validation and number filter', () => {
  const errors = validateCompliance({kind: 'personal', fullName: '', addressLine: '', postcode: 'x', email: 'x', mobile: '1'});
  assert.ok(errors.length >= 5);
  assert.deepEqual(validateCompliance({kind: 'personal', fullName: 'Ada Lovelace', addressLine: '1 Example Street', postcode: 'SW1A 1AA',
    email: 'ada@example.com', mobile: '07700 900000', documentName: 'passport.jpg'}), []);
  const numbers = mockNumbers(3);
  assert.ok(filterNumbers(numbers, numbers[0].e164.slice(-3), 'all').some(n => n.id === numbers[0].id));
  assert.ok(filterNumbers(numbers, '', 'tollFree').every(n => n.type === 'tollFree'));
});

test('mock inventory revalidation marks the 6th number taken; recurring total adds the number fee', async () => {
  const api = createMockConnectApi(0);
  assert.equal(await api.revalidate('mock-0-5'), false);
  assert.equal(await api.revalidate('mock-0-1'), true);
  const plan = MOCK_PLAN_CONFIG.find(p => p.id === 'personal')!;
  assert.equal(recurringTotal(plan, mockNumbers(0)[4]), '£19.98/month');
  assert.equal(recurringTotal(MOCK_PLAN_CONFIG[0], mockNumbers(0)[0]), 'Free');
});

test('mock provisioning can fail without creating a number, and cancel moves to cancellationPending', async () => {
  const api = createMockConnectApi(0);
  await assert.rejects(api.provision('mock-0-0', 'personal', {simulateFailure: true}));
  assert.equal((await api.numbers()).length, 0);
  const record = await api.provision('mock-0-0', 'personal');
  assert.ok(isIllustrativeNumber(record.number.e164));
  assert.equal((await api.cancel(record.id)).state, 'cancellationPending');
  assert.equal((await api.updateSettings(record.id, {voicemail: true})).settings.voicemail, true);
});

test('memorable numbers, usage and lifecycle helpers (t237u)', async () => {
  const {isMemorable, mockUsage, usageFraction, lifecycleProgress, DEFAULT_NUMBER_SETTINGS} = await import('../src/modules/connect/model');
  assert.equal(isMemorable('07700 900111'), true);
  assert.equal(isMemorable('07700 901234'), true);
  assert.equal(isMemorable('07700 900352'), false);
  const usage = mockUsage('owned-x', MOCK_PLAN_CONFIG.find(p => p.id === 'business'));
  assert.equal(usage.textsAllowance, null);
  assert.equal(usage.illustrative, true);
  assert.equal(usageFraction(50, 100), 0.5);
  assert.equal(usageFraction(500, 100), 1);
  assert.equal(usageFraction(5, null), 0);
  assert.equal(lifecycleProgress('active'), 4);
  assert.equal(lifecycleProgress('suspended'), -1);
  assert.equal(DEFAULT_NUMBER_SETTINGS.spamFilter, true);
});
