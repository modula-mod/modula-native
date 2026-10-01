/**
 * Declarative module UI: a small, closed vocabulary of nodes that modules (or data
 * from their backend) can describe screens with, rendered by `NodeRenderer`.
 *
 * `normalizeNodes` is the trust boundary: it never throws, caps size and depth, drops
 * unknown props, turns unknown node types into `unsupported` placeholders, and only
 * lets actions reference names the module registered (no URLs, no code). It is pure so
 * it can be tested without React Native.
 */
export type Tone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger';
export type ActionRef = {action: string; payload?: Record<string, string | number | boolean | null>};

export type Column = {key: string; title: string; align?: 'start' | 'end'; width?: number};
export type FieldSpec = {key: string; label: string; kind: 'text' | 'multiline' | 'number' | 'email' | 'toggle' | 'choice';
  required?: boolean; placeholder?: string; options?: {value: string; label: string}[]; hint?: string};

export type UINode =
  | {type: 'stack'; key: string; gap?: 'sm' | 'md' | 'lg'; children: UINode[]}
  | {type: 'section'; key: string; title?: string; footer?: string; children: UINode[]}
  | {type: 'heading'; key: string; text: string; level: 1 | 2 | 3}
  | {type: 'text'; key: string; text: string; secondary?: boolean}
  | {type: 'badge'; key: string; label: string; tone: Tone}
  | {type: 'notice'; key: string; message: string; tone: Tone; action?: ActionRef & {title: string}}
  | {type: 'button'; key: string; title: string; variant: 'primary' | 'secondary' | 'destructive'; onPress: ActionRef}
  | {type: 'keyValue'; key: string; items: {label: string; value: string}[]}
  | {type: 'list'; key: string; items: {id: string; title: string; subtitle?: string; meta?: string; badges?: {label: string; tone: Tone}[]; onPress?: ActionRef}[]; empty?: string}
  | {type: 'table'; key: string; columns: Column[]; rows: {id: string; cells: Record<string, string>; onPress?: ActionRef}[]; empty?: string}
  | {type: 'form'; key: string; fields: FieldSpec[]; submit: {title: string; action: string}}
  | {type: 'empty'; key: string; title: string; message: string; action?: ActionRef & {title: string}}
  | {type: 'unsupported'; key: string; label: string};

export const NODE_LIMITS = {maxNodes: 400, maxDepth: 8, maxText: 4000, maxRows: 500, maxColumns: 12, maxFields: 40};
const TONES = new Set<Tone>(['neutral', 'accent', 'success', 'warning', 'danger']);
const ACTION = /^[a-z][a-zA-Z0-9.]{0,63}$/;

type Ctx = {count: number; allowedActions: ReadonlySet<string>; seen: Set<string>};
type Raw = Record<string, unknown>;

const obj = (v: unknown): Raw | undefined => v && typeof v === 'object' && !Array.isArray(v) ? v as Raw : undefined;
const text = (v: unknown, max = NODE_LIMITS.maxText): string | undefined =>
  typeof v === 'string' ? v.slice(0, max) : typeof v === 'number' && Number.isFinite(v) ? String(v) : undefined;
const tone = (v: unknown): Tone => TONES.has(v as Tone) ? v as Tone : 'neutral';

function action(v: unknown, ctx: Ctx): ActionRef | undefined {
  const raw = obj(v);
  const name = typeof raw?.action === 'string' ? raw.action : typeof v === 'string' ? v : undefined;
  if (!name || !ACTION.test(name) || !ctx.allowedActions.has(name)) return undefined;
  const payload: ActionRef['payload'] = {};
  for (const [k, value] of Object.entries(obj(raw?.payload) ?? {}).slice(0, 16)) {
    if (value === null || ['string', 'number', 'boolean'].includes(typeof value)) payload[k.slice(0, 64)] = typeof value === 'string' ? value.slice(0, 256) : value as never;
  }
  return Object.keys(payload).length ? {action: name, payload} : {action: name};
}

function key(raw: Raw, path: string, ctx: Ctx): string {
  const candidate = typeof raw.key === 'string' && raw.key ? raw.key.slice(0, 80) : typeof raw.id === 'string' && raw.id ? raw.id.slice(0, 80) : path;
  const unique = ctx.seen.has(candidate) ? `${candidate}~${path}` : candidate;
  ctx.seen.add(unique);
  return unique;
}

function badges(v: unknown): {label: string; tone: Tone}[] | undefined {
  if (!Array.isArray(v)) return undefined;
  const out = v.slice(0, 6).flatMap(b => { const label = text(obj(b)?.label ?? b, 40); return label ? [{label, tone: tone(obj(b)?.tone)}] : []; });
  return out.length ? out : undefined;
}

function node(input: unknown, path: string, depth: number, ctx: Ctx): UINode | undefined {
  if (ctx.count >= NODE_LIMITS.maxNodes) return undefined;
  ctx.count++;
  const raw = obj(input);
  if (!raw) return {type: 'unsupported', key: `bad-${path}`, label: 'Unsupported content'};
  const k = key(raw, path, ctx);
  const children = (): UINode[] => depth >= NODE_LIMITS.maxDepth
    ? [{type: 'unsupported', key: `${k}-deep`, label: 'Content nested too deeply'}]
    : (Array.isArray(raw.children) ? raw.children : []).map((c, i) => node(c, `${path}.${i}`, depth + 1, ctx)).filter((n): n is UINode => Boolean(n));
  switch (raw.type) {
    case 'stack': return {type: 'stack', key: k, gap: raw.gap === 'sm' || raw.gap === 'lg' ? raw.gap : 'md', children: children()};
    case 'section': return {type: 'section', key: k, title: text(raw.title, 120), footer: text(raw.footer, 400), children: children()};
    case 'heading': { const t = text(raw.text, 200); return t ? {type: 'heading', key: k, text: t, level: raw.level === 1 || raw.level === 3 ? raw.level : 2} : undefined; }
    case 'text': { const t = text(raw.text); return t !== undefined ? {type: 'text', key: k, text: t, secondary: raw.secondary === true} : undefined; }
    case 'badge': { const l = text(raw.label, 40); return l ? {type: 'badge', key: k, label: l, tone: tone(raw.tone)} : undefined; }
    case 'notice': {
      const m = text(raw.message, 600); if (!m) return undefined;
      const a = action(raw.action, ctx); const title = text(obj(raw.action)?.title, 40);
      return {type: 'notice', key: k, message: m, tone: raw.tone ? tone(raw.tone) : 'warning', ...(a && title ? {action: {...a, title}} : {})};
    }
    case 'button': {
      const t = text(raw.title, 60); const a = action(raw.onPress ?? raw.action, ctx);
      if (!t) return undefined;
      if (!a) return {type: 'unsupported', key: k, label: `Action unavailable: ${t}`};
      return {type: 'button', key: k, title: t, variant: raw.variant === 'secondary' || raw.variant === 'destructive' ? raw.variant : 'primary', onPress: a};
    }
    case 'keyValue': {
      const items = (Array.isArray(raw.items) ? raw.items : []).slice(0, 60).flatMap(i => {
        const label = text(obj(i)?.label, 80); const value = text(obj(i)?.value, 400);
        return label ? [{label, value: value ?? '—'}] : [];
      });
      return {type: 'keyValue', key: k, items};
    }
    case 'list': {
      const ids = new Set<string>();
      const items = (Array.isArray(raw.items) ? raw.items : []).slice(0, NODE_LIMITS.maxRows).flatMap((i, index) => {
        const item = obj(i); const title = text(item?.title, 200); if (!item || !title) return [];
        let id = text(item.id, 80) ?? `row-${index}`; if (ids.has(id)) id = `${id}~${index}`; ids.add(id);
        const onPress = action(item.onPress, ctx);
        return [{id, title, subtitle: text(item.subtitle, 300), meta: text(item.meta, 80), badges: badges(item.badges), ...(onPress ? {onPress} : {})}];
      });
      return {type: 'list', key: k, items, empty: text(raw.empty, 200)};
    }
    case 'table': {
      const columns = (Array.isArray(raw.columns) ? raw.columns : []).slice(0, NODE_LIMITS.maxColumns).flatMap(c => {
        const col = obj(c); const ck = text(col?.key, 64); const title = text(col?.title, 60);
        if (!col || !ck || !title) return [];
        const width = typeof col.width === 'number' && col.width >= 60 && col.width <= 480 ? col.width : undefined;
        return [{key: ck, title, align: col.align === 'end' ? 'end' as const : 'start' as const, ...(width ? {width} : {})}];
      });
      if (!columns.length) return {type: 'unsupported', key: k, label: 'Table has no columns'};
      const ids = new Set<string>();
      const rows = (Array.isArray(raw.rows) ? raw.rows : []).slice(0, NODE_LIMITS.maxRows).flatMap((r, index) => {
        const row = obj(r); if (!row) return [];
        const source = obj(row.cells) ?? row;
        const cells: Record<string, string> = {};
        for (const col of columns) cells[col.key] = text(source[col.key], 300) ?? '';
        let id = text(row.id, 80) ?? `row-${index}`; if (ids.has(id)) id = `${id}~${index}`; ids.add(id);
        const onPress = action(row.onPress, ctx);
        return [{id, cells, ...(onPress ? {onPress} : {})}];
      });
      return {type: 'table', key: k, columns, rows, empty: text(raw.empty, 200)};
    }
    case 'form': {
      const submitAction = text(obj(raw.submit)?.action, 64);
      if (!submitAction || !ACTION.test(submitAction) || !ctx.allowedActions.has(submitAction)) return {type: 'unsupported', key: k, label: 'Form action unavailable'};
      const keys = new Set<string>();
      const fields = (Array.isArray(raw.fields) ? raw.fields : []).slice(0, NODE_LIMITS.maxFields).flatMap(f => {
        const field = obj(f); const fk = text(field?.key, 64); const label = text(field?.label, 80);
        if (!field || !fk || !label || keys.has(fk)) return []; keys.add(fk);
        const kind = (['text', 'multiline', 'number', 'email', 'toggle', 'choice'] as const).find(x => x === field.kind) ?? 'text';
        const options = kind === 'choice' ? (Array.isArray(field.options) ? field.options : []).slice(0, 20).flatMap(o => {
          const value = text(obj(o)?.value ?? o, 64); const l = text(obj(o)?.label ?? o, 60); return value && l ? [{value, label: l}] : [];
        }) : undefined;
        if (kind === 'choice' && !options?.length) return [];
        return [{key: fk, label, kind, required: field.required === true, placeholder: text(field.placeholder, 80), hint: text(field.hint, 200), ...(options ? {options} : {})}];
      });
      return {type: 'form', key: k, fields, submit: {title: text(obj(raw.submit)?.title, 40) ?? 'Save', action: submitAction}};
    }
    case 'empty': {
      const title = text(raw.title, 120) ?? 'Nothing here yet'; const a = action(raw.action, ctx); const t = text(obj(raw.action)?.title, 40);
      return {type: 'empty', key: k, title, message: text(raw.message, 400) ?? '', ...(a && t ? {action: {...a, title: t}} : {})};
    }
    default:
      return {type: 'unsupported', key: k, label: typeof raw.type === 'string' ? `Unsupported: ${raw.type.slice(0, 40)}` : 'Unsupported content'};
  }
}

export function normalizeNodes(input: unknown, allowedActions: Iterable<string> = []): UINode[] {
  const ctx: Ctx = {count: 0, allowedActions: new Set(allowedActions), seen: new Set()};
  const list = Array.isArray(input) ? input : input === undefined || input === null ? [] : [input];
  const out = list.map((n, i) => node(n, String(i), 0, ctx)).filter((n): n is UINode => Boolean(n));
  if (ctx.count >= NODE_LIMITS.maxNodes) out.push({type: 'unsupported', key: 'limit', label: 'Some content was not shown'});
  return out;
}

/** Validates a form submission against its spec. Returns per-field errors (empty = valid). */
export function validateForm(fields: FieldSpec[], values: Record<string, unknown>): Record<string, string> {
  const errors: Record<string, string> = {};
  for (const field of fields) {
    const value = values[field.key];
    const empty = value === undefined || value === null || (typeof value === 'string' && !value.trim());
    if (field.required && empty && field.kind !== 'toggle') { errors[field.key] = `${field.label} is required`; continue; }
    if (empty) continue;
    if (field.kind === 'number' && !Number.isFinite(Number(value))) errors[field.key] = `${field.label} must be a number`;
    if (field.kind === 'email' && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value))) errors[field.key] = `Enter a valid email`;
    if (field.kind === 'choice' && !field.options?.some(o => o.value === value)) errors[field.key] = `Choose a ${field.label.toLowerCase()}`;
  }
  return errors;
}

/** Column widths for a table: explicit widths win, the rest share by content length (bounded). */
export function columnWidths(columns: Column[], rows: {cells: Record<string, string>}[], charWidth = 8): number[] {
  return columns.map(col => {
    if (col.width) return col.width;
    const longest = Math.max(col.title.length, ...rows.slice(0, 50).map(r => (r.cells[col.key] ?? '').length));
    return Math.min(260, Math.max(80, Math.round(longest * charWidth + 24)));
  });
}
