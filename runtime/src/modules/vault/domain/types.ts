export const VAULT_NOTES_MODULE_ID = 'digital.modula.vault-notes' as const
export const VAULT_NOTES_SLUG = 'vault-notes' as const
export const VAULT_NOTES_NAME = 'Vault Notes' as const
export const VAULT_NOTES_STANDARD_VERSION = '2.1.0' as const
export const VAULT_NOTES_MODULE_VERSION = '1.7.0' as const
export const VAULT_NOTES_MANIFEST_SCHEMA_VERSION = '2.1.0' as const
export const VAULT_NOTES_DATA_SCHEMA_VERSION = '1.0.0' as const

export type VaultDocumentBlockType =
  | 'paragraph'
  | 'heading'
  | 'bullet-list'
  | 'numbered-list'
  | 'checklist'
  | 'quote'
  | 'code'
  | 'divider'
  | 'callout'
  | 'link-preview'
  | 'image-reference'
  | 'file-reference'

export type VaultInlineMarkType = 'bold' | 'italic' | 'strikethrough' | 'code' | 'link'

export type VaultInlineMark = {
  type: VaultInlineMarkType
  href?: string
}

export type VaultDocumentInline = {
  text: string
  marks?: VaultInlineMark[]
}

export type VaultDocumentBlock = {
  id: string
  type: VaultDocumentBlockType
  text?: string
  level?: 1 | 2 | 3
  items?: string[]
  checked?: boolean[]
  language?: string
  url?: string
  title?: string
  sourceRef?: string
  alt?: string
  inlines?: VaultDocumentInline[]
}

export type VaultStructuredDocument = {
  schemaVersion: '1.0.0'
  blocks: VaultDocumentBlock[]
}

export type VaultSavedSourceReference = {
  sourceType: 'modula-post' | 'modula-comment' | 'web-url' | 'file' | 'manual'
  sourceId?: string
  sourceUrl?: string
  title?: string
  authorDisplayName?: string
  capturedAt: string
  metadata?: Record<string, unknown>
}

export type VaultNoteRecord = {
  id: string
  title: string
  document: VaultStructuredDocument
  plainTextProjection: string
  folderId?: string
  tagIds: string[]
  pinned: boolean
  favourite: boolean
  archived: boolean
  source?: VaultSavedSourceReference
  revision: number
  createdAt: string
  updatedAt: string
  deletedAt?: string
  dataSchemaVersion: '1.0.0'
}

export type VaultFolderRecord = {
  id: string
  name: string
  parentFolderId?: string
  position: number
  createdAt: string
  updatedAt: string
}

export type VaultTagRecord = {
  id: string
  name: string
  normalizedName: string
  createdAt: string
  updatedAt: string
}

export type VaultNoteLinkRecord = {
  id: string
  sourceNoteId: string
  targetNoteId: string
  linkType: 'internal' | 'related' | 'source'
  createdAt: string
}

export type VaultNoteVersionRecord = {
  id: string
  noteId: string
  revision: number
  title: string
  document: VaultStructuredDocument
  createdAt: string
  createdBy: string
  changeSource: 'manual' | 'restore' | 'import' | 'ai-assisted'
}

export type VaultExportFormat = 'json' | 'markdown' | 'plain-text' | 'zip'

export type VaultExportManifest = {
  moduleId: typeof VAULT_NOTES_MODULE_ID
  moduleVersion: typeof VAULT_NOTES_MODULE_VERSION
  standardVersion: typeof VAULT_NOTES_STANDARD_VERSION
  dataSchemaVersion: typeof VAULT_NOTES_DATA_SCHEMA_VERSION
  exportedAt: string
  recordCount: number
}

export type VaultModuleEvent = {
  type: string
  version: '1.0.0'
  dataClassification: 'private' | 'sensitive' | 'internal'
  retention: string
  sourceRecordVersion: number
  accountId: string
  actorId: string
  requestId: string
  correlationId: string
  payload: Record<string, unknown>
}
