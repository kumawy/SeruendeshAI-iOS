# SeruendeshAI UX refinement

## Authorized outcome
Implement the user's responses to the 57-point audit, retaining the current native SwiftUI identity, icon-only tabs, local data by default, and photo attachments. Do not add a demo badge. Remove route and event bookmarking from all user flows; Favorites contains places only. Automatic walk history is distinct from bookmarking.

## Recovery point
Before implementation, the complete current source was committed and pushed to the new private repository https://github.com/kumawy/pet_project. Both main and tag backup-before-ux-2026-10-24 point to 8c4ff29540d134cc00bbd98439e930ae54d8cf65. Work in this repository only; no branches in other repositories.

## Behavior
- Persist walk sessions, drafts and per-answer recommendation context. Add a reachable Journal in chat and profile, plus New Walk. Opening an old recommendation restores its own places, plan and preferences.
- Plans respect origin, duration, free-only and children preferences. A filter change during a request restarts or visibly cancels the request. Metadata can retry after transient failure. Preserve useful server facts and return/budget information.
- Allow removing and reordering plan stops with honest recalculated estimates. Share navigable locations and ordered stops. External map actions must match the provider capability; Yandex opens a place and is labeled accordingly.
- Keep photo attachments functional locally. Do not invent a backend photo location contract; defer that server-specific addition. Downsample photos off the main actor and enable copy/zoom.
- Remove event hearts, saved-only filters and event-bookmark actions. Improve date rollover, category visibility, transactional date selection and session times; add venue directions and user-reviewed calendar export.
- Restore account favorites from an account-scoped cache while verifying the session; distinguish loading, offline, empty and failed states. Route the signed-in Favorites account button to Profile. Provide Undo for removing a saved place.
- Default to system appearance, unify friendly informal Russian copy, correct plural forms, support current durations and larger touch areas. Keep profile reachable on all top-level tabs. Explain local storage where it affects a user's decision.
- Replace the spiral splash with a short brand greeting and crossfade, independent of backend readiness, with Reduce Motion and cancellation support. No Metal spiral remains in the launch path.
- Improve map clarity using native MapKit with local POIs (Apple map tiles are independent of the app backend), consistent fixture facts and honest origin labels. No GPS claim without actual location. Preserve local recommendation/chat behavior.
- Motion uses native, short state transitions, restrained springs, numeric transitions and meaningful feedback. Respect Reduce Motion; no decorative delays or cascading feed animations.

## Validation
Meaningful core regressions for persistence/context, plan constraints, cancellation/retry and account cache; update tests for removed bookmark capabilities and quick splash. Build the iOS app and run representative UI flows including history, plan edits, events, accessibility text and both themes. Existing unrelated live-account tests must not create/delete real accounts during this task.
