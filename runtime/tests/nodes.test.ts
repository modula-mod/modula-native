import test from 'node:test';
import assert from 'node:assert/strict';
import {columnWidths, normalizeNodes, NODE_LIMITS, validateForm, type UINode} from '../src/ui/nodes';

const crmScreen = [
  {type: 'heading', level: 1, text: 'Acme Ltd'},
  {type: 'section', title: 'Details', children: [
    {type: 'keyValue', items: [{label: 'Owner', value: 'Ada'}, {label: 'Stage', value: 'Proposal'}, {label: 'Value', value: 12000}]},
  ]},
  {type: 'table', key: 'deals', columns: [{key: 'name', title: 'Deal'}, {key: 'value', title: 'Value', align: 'end'}],
    rows: [{id: 'd1', cells: {name: 'Renewal', value: '£4,000'}, onPress: {action: 'openDeal', payload: {id: 'd1'}}}, {id: 'd1', name: 'Upsell', value: 900}]},
  {type: 'form', fields: [{key: 'name', label: 'Name', required: true}, {key: 'email', label: 'Email', kind: 'email'},
    {key: 'stage', label: 'Stage', kind: 'choice', options: ['Lead', 'Won']}], submit: {title: 'Save contact', action: 'saveContact'}},
];

test('a CRM-style screen normalises into the closed vocabulary', () => {
  const nodes = normalizeNodes(crmScreen, ['openDeal', 'saveContact']);
  assert.deepEqual(nodes.map(n => n.type), ['heading', 'section', 'table', 'form']);
  const kv = (nodes[1] as Extract<UINode, {type: 'section'}>).children[0] as Extract<UINode, {type: 'keyValue'}>;
  assert.deepEqual(kv.items[2], {label: 'Value', value: '12000'}, 'numbers are shown as text');
  const table = nodes[2] as Extract<UINode, {type: 'table'}>;
  assert.equal(table.columns[1]!.align, 'end');
  assert.deepEqual(table.rows.map(r => r.id), ['d1', 'd1~1'], 'duplicate row ids are made unique');
  assert.deepEqual(table.rows[0]!.onPress, {action: 'openDeal', payload: {id: 'd1'}});
  assert.deepEqual(table.rows[1]!.cells, {name: 'Upsell', value: '900'}, 'flat rows are accepted');
  const form = nodes[3] as Extract<UINode, {type: 'form'}>;
  assert.equal(form.fields[2]!.options!.length, 2);
});

test('unregistered actions, unknown nodes and hostile values fall back safely', () => {
  const nodes = normalizeNodes([
    {type: 'button', title: 'Delete everything', onPress: {action: 'wipe'}},
    {type: 'button', title: 'Open', onPress: 'javascript:alert(1)'},
    {type: 'kanban', columns: []},
    'not a node', null,
    {type: 'list', items: [{title: 'Row', onPress: {action: 'openDeal', payload: {nested: {x: 1}, ok: 'yes'}}}]},
    {type: 'form', fields: [], submit: {action: 'notRegistered'}},
  ], ['openDeal']);
  assert.deepEqual(nodes.map(n => n.type), ['unsupported', 'unsupported', 'unsupported', 'unsupported', 'unsupported', 'list', 'unsupported']);
  assert.match((nodes[0] as {label: string}).label, /Action unavailable/);
  assert.match((nodes[2] as {label: string}).label, /kanban/);
  const list = nodes[5] as Extract<UINode, {type: 'list'}>;
  assert.deepEqual(list.items[0]!.onPress, {action: 'openDeal', payload: {ok: 'yes'}}, 'only scalar payload values survive');
});

test('size and depth limits keep rendering bounded', () => {
  let deep: unknown = {type: 'text', text: 'leaf'};
  for (let i = 0; i < 20; i++) deep = {type: 'stack', children: [deep]};
  const [root] = normalizeNodes(deep);
  let n: UINode | undefined = root; let depth = 0;
  while (n && n.type === 'stack') { n = n.children[0]; depth++; }
  assert.equal(depth, NODE_LIMITS.maxDepth + 1, "levels 0…maxDepth render, deeper content is replaced");
  assert.equal(n?.type, 'unsupported');
  const many = normalizeNodes(Array.from({length: 1000}, (_, i) => ({type: 'text', text: `t${i}`})));
  assert.equal(many.length, NODE_LIMITS.maxNodes + 1);
  assert.equal(many.at(-1)!.type, 'unsupported');
  const big = normalizeNodes({type: 'text', text: 'x'.repeat(100_000)});
  assert.equal((big[0] as {text: string}).text.length, NODE_LIMITS.maxText);
});

test('form validation and table sizing', () => {
  const form = normalizeNodes(crmScreen[3], ['saveContact'])[0] as Extract<UINode, {type: 'form'}>;
  assert.deepEqual(validateForm(form.fields, {}), {name: 'Name is required'});
  assert.deepEqual(validateForm(form.fields, {name: 'Ada', email: 'nope', stage: 'Lost'}), {email: 'Enter a valid email', stage: 'Choose a stage'});
  assert.deepEqual(validateForm(form.fields, {name: 'Ada', email: 'ada@example.com', stage: 'Won'}), {});
  const widths = columnWidths([{key: 'a', title: 'A'}, {key: 'b', title: 'B', width: 200}], [{cells: {a: 'x'.repeat(200), b: ''}}]);
  assert.deepEqual(widths, [260, 200]);
});

test('the CRM reference screen uses only supported nodes (plus the deliberate fallback)', async () => {
  const {crmAccountScreen, CRM_ACTIONS} = await import('../src/modules/gallery/crmSample');
  const nodes = normalizeNodes(crmAccountScreen, CRM_ACTIONS);
  const flat: UINode[] = [];
  const walk = (list: UINode[]) => list.forEach(n => { flat.push(n); if ('children' in n) walk(n.children); });
  walk(nodes);
  assert.deepEqual(flat.filter(n => n.type === 'unsupported').map(n => (n as {label: string}).label), ['Unsupported: timeline']);
  assert.ok(flat.some(n => n.type === 'table') && flat.some(n => n.type === 'form') && flat.some(n => n.type === 'keyValue'));
});
