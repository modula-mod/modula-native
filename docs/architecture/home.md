# Home (N3C)

Home is the first real native social surface. Routes:

```text
/home → /home/following
/home/following
/home/for-you
/home/modules
```

Modes live only on `ModulaContextRail`. The Home shell accessory is Compose / Summary / Tools — never Search and never a second Following|For You|Modules tab strip.

## Ownership

```text
HomeStore → GreenfieldHomeRepository → GET /v1/feed/home
Social/Post* → shared PostCard / PostActions
ModulaProgressiveHeader → scroll-edge dissolve (soft edge + public fallback)
```

Greenfield owns Following graph composition, For You `ranking-v1`, and Modules chrono. The client does not fan out profile posts.

Pinned content does not need a visible bar. Scrolling content should dissolve progressively into the top chrome.

## Auth

Following requires identity. Signed-out Following shows Sign In with return `/home/following`. For You and Modules remain publicly readable.

## Summary

`FeedSummarySource.aggregate` today; `.agent` reserved for a future AI summarizer without replacing the sheet UI.
