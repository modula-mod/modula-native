/**
 * Pure helpers behind the reusable record components in `records.tsx` (tables and
 * forms). They encode no screen schema of their own: the standard host components for
 * the modula.frontend.1.0 format (see the modula-product-standard repo) will feed them.
 * Kept free of React Native so they can be unit tested in Node.
 */
export type Column = {key: string; title: string; align?: 'start' | 'end'; width?: number};
export type FieldSpec = {key: string; label: string; kind: 'text' | 'multiline' | 'number' | 'email' | 'toggle' | 'choice';
  required?: boolean; placeholder?: string; options?: {value: string; label: string}[]; hint?: string};

/** Validates a form submission against its fields. Returns per-field errors (empty = valid). */
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
