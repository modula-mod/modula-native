/**
 * A CRM account page described with the declarative node vocabulary. It is the
 * reference for docs/architecture/module-authoring.md and renders in the Runtime
 * Diagnostic "Component gallery". Data like this would normally come from
 * backend.records.* results mapped by the module.
 */
export const CRM_ACTIONS = ['openDeal', 'saveContact', 'logCall'] as const;

export const crmAccountScreen = [
  {type: 'heading', level: 1, text: 'Acme Ltd'},
  {type: 'stack', gap: 'sm', children: [
    {type: 'badge', label: 'Customer', tone: 'success'},
    {type: 'text', secondary: true, text: 'Manufacturing · London · Owner: Ada Lovelace'},
  ]},
  {type: 'notice', tone: 'warning', message: 'Renewal is due in 14 days.', action: {action: 'logCall', title: 'Log call'}},
  {type: 'section', title: 'Details', children: [
    {type: 'keyValue', items: [
      {label: 'Stage', value: 'Proposal'}, {label: 'Annual value', value: '£48,000'},
      {label: 'Primary contact', value: 'Grace Hopper'}, {label: 'Last activity', value: 'Yesterday'},
    ]},
  ]},
  {type: 'section', title: 'Open deals', footer: 'Tap a deal to open it.', children: [
    {type: 'table', columns: [{key: 'name', title: 'Deal'}, {key: 'stage', title: 'Stage'}, {key: 'value', title: 'Value', align: 'end'}, {key: 'close', title: 'Close'}],
      rows: [
        {id: 'd-renewal', cells: {name: 'Annual renewal', stage: 'Proposal', value: '£48,000', close: '15 Oct'}, onPress: {action: 'openDeal', payload: {id: 'd-renewal'}}},
        {id: 'd-upsell', cells: {name: 'Analytics add-on', stage: 'Qualified', value: '£9,600', close: '2 Nov'}, onPress: {action: 'openDeal', payload: {id: 'd-upsell'}}},
        {id: 'd-training', cells: {name: 'Team training', stage: 'Lead', value: '£2,400', close: '—'}, onPress: {action: 'openDeal', payload: {id: 'd-training'}}},
      ]},
  ]},
  {type: 'section', title: 'Contacts', children: [
    {type: 'list', items: [
      {id: 'c-grace', title: 'Grace Hopper', subtitle: 'Head of Operations', meta: 'grace@acme.test', badges: [{label: 'Primary', tone: 'accent'}]},
      {id: 'c-alan', title: 'Alan Turing', subtitle: 'Finance', meta: 'alan@acme.test'},
    ]},
  ]},
  {type: 'section', title: 'New contact', children: [
    {type: 'form', submit: {title: 'Save contact', action: 'saveContact'}, fields: [
      {key: 'name', label: 'Name', required: true, placeholder: 'Full name'},
      {key: 'email', label: 'Email', kind: 'email', placeholder: 'name@company.com'},
      {key: 'role', label: 'Role', kind: 'choice', options: [{value: 'buyer', label: 'Buyer'}, {value: 'user', label: 'User'}, {value: 'exec', label: 'Exec'}]},
      {key: 'newsletter', label: 'Send product updates', kind: 'toggle'},
    ]},
  ]},
  {type: 'timeline', items: []},
];
