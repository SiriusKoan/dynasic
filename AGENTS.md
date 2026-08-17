# DynamicLyrics Agent Instructions

## Scope

DynamicLyrics is a native macOS lyrics overlay for Apple Music only.

Do not add support for:
- Spotify
- YouTube
- iOS
- Shazam
- translation
- word-level karaoke

## Architecture

UI must not access Music.app, networking, cache, or filesystem directly.

Dependencies flow:

UI
-> LyricsCoordinator
-> domain services
-> infrastructure adapters

LyricsCore must remain independently testable.

## Apple Music

Never assume an Apple Music observation mechanism works.

The selected backend must be recorded in:
docs/apple-music-observation.json

Do not introduce private or undocumented Apple frameworks without explicit user approval.

## Concurrency

Prefer structured Swift concurrency.

Avoid:
- detached tasks unless necessary
- unstructured background loops
- arbitrary sleeps in tests

All long-lived Tasks must have defined ownership and cancellation.

## Networking

Network access must go through HTTPClient.

Unit tests must never require Internet access.

## Time

Time-dependent components must use injectable clocks.

Tests must not wait for real time.

## Testing

After every milestone run:

./scripts/check.sh

A milestone is not complete if this command fails.

Bug fixes should include regression tests when practical.

## Xcode

Keep the Xcode app target thin.

Do not manually modify project.pbxproj unless necessary.

Prefer source-controlled Swift code and Swift packages.

## Completion report

For each milestone report:

1. Files changed
2. Architecture decisions
3. Tests added
4. Commands executed
5. Build/test output summary
6. Manual verification needed
7. Known limitations

Do not claim external integrations are verified unless they were actually exercised.
