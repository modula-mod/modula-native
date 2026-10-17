# Product UI native renderer

The renderer consumes MPS frontend 1.0 (`modula.frontend.1.0`).

## Baseline primitives (native)

Button, Text, Field, Form/section, List/recordList, Search, Filter, Sort, Menu, Toolbar, Sheet, Metadata, Badge, LoadingState, ErrorState, EmptyState, stack/row/grid/scroll.

Provenance: `native`.

## Advanced components

| Component | Capability | Renderer |
| --- | --- | --- |
| richText / richDocumentEditor | `ui.richText@1` | Native TextEditor with lossless plain-text projection |
| editorToolbar | `ui.richText.commands@1` | Native command toolbar |
| graph | `ui.graph@1` | Declared list fallback |
| revisionBrowser, attachmentGallery, propertyEditor, referencePicker, recordTable, recordBoard, commandMenu | matching `ui.*@1` | Contract-approved fallback, never a silent text field |

Required unavailable capability → `CAPABILITY_UNAVAILABLE`. Optional capability uses only the module's declared fallback.

Forbidden keys (`script`, `rawjs`, `webview`, `eval`, …) fail closed before render.
