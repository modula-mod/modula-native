import {createDocumentFromText, plainTextProjection, validateStructuredDocument} from './domain/document';
import {VAULT_NOTES_DATA_SCHEMA_VERSION, type VaultStructuredDocument} from './domain/types';
import {isPlainDocument} from './editing';
export type NoteData = {
  title: string; document: VaultStructuredDocument; plainTextProjection: string;
  tagIds: string[]; pinned: boolean; favourite: boolean; archived: boolean;
  dataSchemaVersion: '1.0.0'; folderId?: string; source?: unknown;
};
export type NoteRow = {record_id: string; revision: number; data: NoteData; updated_at?: string; created_at?: string};
export type NotePage = {items: NoteRow[]; nextCursor: string | null};
export type NoteSort = 'updatedAt' | 'createdAt' | 'title';

// Editing rich documents through a plain text field would destroy structure.
export function textEditable(document: VaultStructuredDocument): boolean {
  return isPlainDocument(document);
}

function checkTitle(title: string): string {
  title = title.trim();
  if (!title || title.length > 240) throw new Error('Use a title of 1–240 characters.');
  return title;
}

function finish(title: string, document: VaultStructuredDocument, previous: NoteData | undefined, extra: Partial<NoteData>): NoteData {
  return {...(previous ?? {tagIds: [], pinned: false, favourite: false, archived: false}), ...extra, title, document,
    plainTextProjection: plainTextProjection(document), dataSchemaVersion: VAULT_NOTES_DATA_SCHEMA_VERSION};
}

export function saveData(title: string, text: string, previous?: NoteData, extra: Partial<NoteData> = {}): NoteData {
  title = checkTitle(title);
  if (!text.trim()) throw new Error('Add note content before saving.');
  const unchanged = previous && text === previous.plainTextProjection;
  if (previous && !unchanged && !textEditable(previous.document)) throw new Error('This document requires the full editor.');
  const document = unchanged ? previous.document : createDocumentFromText(text);
  if (!validateStructuredDocument(document).valid) throw new Error('The note exceeds the supported document limits.');
  const data = finish(title, document, previous, extra);
  return unchanged ? {...data, plainTextProjection: previous.plainTextProjection} : data;
}

/** Save path for structured (block-edited) documents. */
export function saveDocumentData(title: string, document: VaultStructuredDocument, previous?: NoteData, extra: Partial<NoteData> = {}): NoteData {
  title = checkTitle(title);
  if (!document.blocks.length) throw new Error('Add note content before saving.');
  const result = validateStructuredDocument(document);
  if (!result.valid) {
    throw new Error(result.issues.some(issue => issue.endsWith('UNKNOWN_TYPE'))
      ? 'This note has content from a newer Vault version and can’t be saved here.'
      : 'The note exceeds the supported document limits.');
  }
  return finish(title, document, previous, extra);
}

/** Pinned first, then the server order (which already follows the chosen sort). */
export function orderForDisplay(rows: NoteRow[]): NoteRow[] {
  return [...rows.filter(row => row.data.pinned), ...rows.filter(row => !row.data.pinned)];
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** "Just now", "5 min ago", "3 h ago", "Yesterday", "12 Sep", "12 Sep 2025". Locale-free on purpose (Hermes Intl varies). */
export function relativeTime(iso: string | undefined, now: number = Date.now()): string | undefined {
  if (!iso) return undefined;
  const time = Date.parse(iso);
  if (!Number.isFinite(time)) return undefined;
  const seconds = Math.max(0, (now - time) / 1000);
  if (seconds < 60) return 'Just now';
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`;
  if (seconds < 86_400) return `${Math.floor(seconds / 3600)} h ago`;
  if (seconds < 172_800) return 'Yesterday';
  const date = new Date(time);
  const current = new Date(now);
  const base = `${date.getDate()} ${MONTHS[date.getMonth()]}`;
  return date.getFullYear() === current.getFullYear() ? base : `${base} ${date.getFullYear()}`;
}
