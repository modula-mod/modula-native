# Discover architecture (N3B)

Discover is a native SwiftUI destination. React Native still begins only at `ModuleHost` for `/module/:moduleId`.

## Ownership

| Layer | Owner |
|---|---|
| Global tab | Home / **Discover** / Modules / Activity / Profile |
| Discover scope | `DiscoverScopePicker` bound to `/discover/{trending,people,topics,posts,modules}` via `replaceContext` |
| Tools | `ShellAccessoryHost` — Search, Filters, Refresh |
| Query | Canonical `/search` (`SearchScreen`) |
| Data | `DiscoverStore` → `GreenfieldDiscoverRepository` → `GreenfieldClient` |
| Trending canvas | `DiscoverDashboardView` (model remains `DiscoverDashboard`) |
| Modules | Product Hub catalogue + `ProductCard` / `InstallStateButton` |
| People detail | `/profile/:handle` |
| Post detail | `/post/:postId` |

Do not add a Discover right rail. Do not add `/discover/search`.

## Chrome

`ShellChromePolicy`:

- `/discover/*` — tab visible, rail hidden, Discover tools accessory visible
- `/search/*` — tab visible, Discover accessory hidden (Search owns the field)
- `/product-hub/module/*` — Product Hub chrome, not Discover tools
- `/auth/*` `/settings/*` `/module/*` — unchanged from N3A

Switching Discover scopes replaces the Discover tab root. Opening Search **pushes** on that stack so back restores scope, filters, and scroll-backed views. Profile, post, and module detail opened from Discover/Search also **push** on the Discover stack (`NavigationCoordinator.push`) so Back does not steal the Profile or Modules tab roots.

## Data

See `docs/migration/discover-backend.md`. N3B uses existing Greenfield surfaces only: `/v1/discover`, `/v1/search`, profile posts, registry products, follow mutate. No recommendation engine.

Labels stay truthful: Trending, Featured, From Modula. Never For You until a personalization contract exists.

Topic taps use canonical `/search/topics?q=` and resolve against `trendingTopics` from `/v1/discover`. Greenfield Search `entityType=topic` is not a real index filter; N3B does not send users into an empty search index for topics.

Featured modules use payload `moduleId` / `catalogueId` when it is a canonical dotted catalogue id. Name/slug resolve remains a temporary bridge until production `/v1/discover` emits catalogue `moduleId` values. There is no client username denylist; fixture leakage is a Greenfield production eligibility issue.
