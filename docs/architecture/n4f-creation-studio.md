# N4F — Creation Studio

Native creation architecture. One studio for every `CreationKind`. Production publishing follows `CreationCapabilities` from Greenfield truth.

```text
Consume → interact → create → publish → appear everywhere
```

## Domain

- `CreationKind`: post, photo, video, link, poll, carousel, audio, movie, story, reel
- `CreationDraft`: text, media refs, link, poll, audience, mentions, location, accessibility, state
- `CreationCapabilities`: honest production flags
- `PublishingRepository` / `MediaUploading`: composer never talks to URLSession

## Studio

Cancel / audience / writing region / attachments / tool dock / Post.

No “CREATE A POST” hero. No WebView. No React Native. No Hermes on this path.

Unavailable kinds are hidden (or a deliberate unavailable state on their route). Users never compose for ten minutes against a dead Publish button.

## Drafts

Local, account-namespaced (`accountID / draftID`). Autosave. Restore prompt. Discard removes owned draft media. Published drafts are removed. Clear cache must not touch drafts.

## Publishing

Server returns a canonical `SocialPost` → `PostStateStore` → Home (public) / Profile posts cache → dismiss. No optimistic global “it’s live”. Failure copy: “Couldn't publish your post. Your draft is safe.”

## Chrome

All `/compose/*`: tab bar, root accessory, and context rail hidden.
