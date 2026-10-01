import type {NoteRow} from './model';

/**
 * Backend rows are untrusted. One row with a missing `data` object or title used to
 * throw inside render (`row.data.archived`) and take the whole module down. Drop rows
 * without an identity, repair the display fields of the rest, and de-duplicate ids
 * (pagination can return an item twice when notes change between pages).
 */
export function normalizeNoteRows(items: unknown, existing: NoteRow[] = []): NoteRow[] {
  const seen = new Set(existing.map(row => row.record_id));
  const result: NoteRow[] = [];
  for (const raw of Array.isArray(items) ? items : []) {
    if (!raw || typeof raw !== 'object') continue;
    const row = raw as Partial<NoteRow> & {data?: unknown};
    if (typeof row.record_id !== 'string' || !row.record_id || seen.has(row.record_id)) continue;
    seen.add(row.record_id);
    const data = row.data && typeof row.data === 'object' ? row.data as Partial<NoteRow['data']> : {};
    const title = typeof data.title === 'string' && data.title.trim() ? data.title : 'Untitled note';
    result.push({
      record_id: row.record_id,
      revision: typeof row.revision === 'number' ? row.revision : 0,
      data: {
        ...(data as NoteRow['data']),
        title,
        plainTextProjection: typeof data.plainTextProjection === 'string' ? data.plainTextProjection : '',
        archived: data.archived === true,
        pinned: data.pinned === true,
        tagIds: Array.isArray(data.tagIds) ? data.tagIds : [],
      },
    });
  }
  return result;
}
