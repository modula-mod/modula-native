import test from 'node:test';
import assert from 'node:assert/strict';
import {columnWidths, validateForm, type FieldSpec} from '../src/ui/forms';

const fields: FieldSpec[] = [
  {key: 'name', label: 'Name', kind: 'text', required: true},
  {key: 'email', label: 'Email', kind: 'email'},
  {key: 'stage', label: 'Stage', kind: 'choice', options: [{value: 'Lead', label: 'Lead'}, {value: 'Won', label: 'Won'}]},
];

test('form validation reports required, email and choice errors', () => {
  assert.deepEqual(validateForm(fields, {}), {name: 'Name is required'});
  assert.deepEqual(validateForm(fields, {name: 'Ada', email: 'nope', stage: 'Lost'}), {email: 'Enter a valid email', stage: 'Choose a stage'});
  assert.deepEqual(validateForm(fields, {name: 'Ada', email: 'ada@example.com', stage: 'Won'}), {});
});

test('table column widths are bounded and explicit widths win', () => {
  const widths = columnWidths([{key: 'a', title: 'A'}, {key: 'b', title: 'B', width: 200}], [{cells: {a: 'x'.repeat(200), b: ''}}]);
  assert.deepEqual(widths, [260, 200]);
});
