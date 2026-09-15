# N3B acceptance notes

Branch: `cursor/phase-n3b-ios-discover-6553`
Baseline: N3A `cursor/phase-n3a-ios-activity-auth-54cd` @ `80e5e30` (N3A not merged to `main`)

## Implemented in-repo

- Greenfield audit: `docs/migration/discover-backend.md`
- Native `DiscoverStore` / `GreenfieldDiscoverRepository`
- Scopes: Trending, People, Topics, Posts, Modules with independent load/filter state
- Canonical Search via `/search` and `GET /v1/search`
- Topic results use Discover `trendingTopics` (Greenfield has no `entityType=topic` index)
- Featured modules prefer canonical `moduleId` when the payload includes it
- Discover tools accessory: Search / Filters / Refresh
- Product Hub component reuse for modules
- Follow mutate through authenticated `GreenfieldClient`
- Discover/Search push profile, post, and module detail on the Discover stack
- Unit tests: `DiscoverTests.swift`; UI scaffold `N3BDiscoverUITests`

## OPEN (Mac + device)

- Private-worker Shell tool is non-functional in this run (`no exit status` / spawn getter error), so git commit/push, `xcodebuild`, Node 22 checks, and UI tests could not be executed here
- Production Discover fixture leak is a Greenfield eligibility issue; `ssh modula-vps` is required to patch `services/greenfield-api`
- Physical device (Xcode device support may still be OPEN)
- Metro-free Release launch with Discover data

## Verdict

PARTIAL until Mac simulator/device gates close. Architecture and Greenfield contracts are implemented in-repo.
