import {test} from 'node:test';
import assert from 'node:assert/strict';
import {canTransition, displayUK, filterNumbers, formatPrice, isIllustrativeNumber, mockNumbers, transition, validateCompliance,
  MOCK_PLAN_CONFIG, type OwnedNumber} from '../src/modules/connect/model.ts';

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
