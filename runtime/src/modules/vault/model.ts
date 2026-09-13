import {createDocumentFromText, plainTextProjection, validateStructuredDocument} from './domain/document';
import {VAULT_NOTES_DATA_SCHEMA_VERSION, type VaultStructuredDocument} from './domain/types';
export type NoteData = {
  title: string; document: VaultStructuredDocument; plainTextProjection: string;
  tagIds: string[]; pinned: boolean; favourite: boolean; archived: boolean;
  dataSchemaVersion: '1.0.0'; folderId?: string; source?: unknown;
};
export type NoteRow = {record_id: string; revision: number; data: NoteData};
export type NotePage = {items: NoteRow[]; nextCursor: string | null};
// Editing rich documents through a plain text field would destroy structure.
export function textEditable(document: VaultStructuredDocument): boolean {
  return validateStructuredDocument(document).valid && document.blocks.every(block =>
    block.type === 'paragraph' && Object.keys(block).every(key => ['id','type','text'].includes(key)));
}
export function saveData(title: string, text: string, previous?: NoteData): NoteData {
  title = title.trim();
  if (!title || title.length > 240) throw new Error('Use a title of 1–240 characters.');
  if (!text.trim()) throw new Error('Add note content before saving.');
  const unchanged = previous && text === previous.plainTextProjection;
  if (previous && !unchanged && !textEditable(previous.document)) throw new Error('This document requires the full editor.');
  const document = unchanged ? previous.document : createDocumentFromText(text);
  if (!validateStructuredDocument(document).valid) throw new Error('The note exceeds the supported document limits.');
  return {...(previous ?? {tagIds:[],pinned:false,favourite:false,archived:false}),title,document,
    plainTextProjection:unchanged ? previous.plainTextProjection : plainTextProjection(document),dataSchemaVersion:VAULT_NOTES_DATA_SCHEMA_VERSION};
}
