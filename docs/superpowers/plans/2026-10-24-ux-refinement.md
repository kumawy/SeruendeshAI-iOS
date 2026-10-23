# SeruendeshAI UX refinement implementation plan

> **For agentic workers:** Use subagent-driven-development for independent owned files; root integrates and verifies. Do not commit or push worker changes.

**Goal:** Complete the authorized audit improvements while preserving a verified private recovery point.

**Architecture:** Keep AppModel as the observable owner. Add Codable per-answer context and bounded persistent walk journal, pure presentation helpers, and account-scoped cached favorites. Native SwiftUI views consume these models and native MapKit handles map presentation.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing/XCTest, MapKit, EventKitUI, ImageIO; iOS 26+.

**Spec:** ../specs/2026-10-24-ux-refinement.md

## Global constraints
- Backup verified before changes; current branch main in kumawy/pet_project only.
- Local data and photos remain the default; no demo badge.
- No route/event bookmarking UI. Keep only place Favorites; automatic history is separate.
- Preserve icon-only tabs, mascot identity, native controls and light/dark support.
- Respect Reduce Motion and use current safe-area/layout inputs.
- Root owns AppRootView, all project generation, shared UI integration, account/profile, maps and final UI tests.

## Review focus
- A stale asynchronous reply cannot overwrite a restored journal entry or new walk.
- Changing a filter must not leave an unexplained unanswered message or conflicting plan.
- Cached account data must never appear under another account after logout, expiry or deletion.
- Older persisted data and empty/corrupt history caches must be safe to load.
- User-selected text size must not overflow icons/actions; no appearance or animation delays obscure the primary task.

## Task 1: State, history and constraint-correct plans (worker core)
Files: Core/AppModel.swift, Models.swift, BackendAPI.swift, BackendMapping.swift, new Core/WalkJournal.swift and core regression tests.
Interfaces: app.journalEntries:[WalkJournalEntry]; app.restoreJournalEntry(id:UUID); app.deleteJournalEntry(id:UUID); app.startNewWalk(); app.openRecommendation(_ message:ChatMessage); app.updatePlan(placeIDs:[String]). WalkJournalEntry exposes id,title,updatedAt,origin,duration. ChatMessage exposes snapshot:RecommendationSnapshot? with context, places, plan.
- [ ] Add and observe failing persistence/context/constraints/metadata regression tests.
- [ ] Implement journal and per-answer snapshots with bounded photo retention and safe legacy decoding.
- [ ] Implement consistent local planning, live plan constraints, metadata retry and explanatory request cancellation/restart.
- [ ] Preserve useful place/route facts and semantic date/number helpers as needed.
- [ ] Run relevant core tests and report interfaces and remaining integration needs.

## Task 2: Events without bookmarks (worker events)
Files: Features/EventsView.swift, new event calendar/presentation helpers, EventsEmptyState.swift and event-focused tests. Do not edit Models/AppModel; coordinate required fields with core.
- [ ] Remove every event save action and saved-only filter.
- [ ] Make date selection transactional, refresh current day, show active categories and actual session times.
- [ ] Add venue map action and EventKitUI user-reviewed calendar export.
- [ ] Improve accessibility and restrained filter/count transitions; update event tests without external account actions.

## Task 3: Quick splash (worker splash)
Files: SeruSplash/*, Core/SplashModel.swift and splash-focused tests. Do not edit project.yml or pbxproj; root regenerates once.
- [ ] Establish new quick-launch timing assertions, then remove spiral and long handoff from launch.
- [ ] Use a short greeting/crossfade with immediate fallback, Reduce Motion, background cancellation and deep-link continuity.
- [ ] Update splash tests and report deleted/created source memberships.

## Task 4: Account cache, journal entry points and place Favorites (root / later worker)
Files: AccountStore.swift, AccountView.swift, ProfileView.swift, SavedView.swift, new JournalView/ProfilePreferences, related tests.
- [ ] Test account-scoped cache restore, session isolation, failed refresh vs empty and Undo.
- [ ] Add Journal/New Walk and local profile display settings; route account entry correctly.
- [ ] Unify saved-place facts, empty copy and theme layers. Explain device/account storage accurately.

## Task 5: Walk UI, maps, photo and deliberate motion (root / later worker)
Files: WalkView, ChatScreen, ChatComposer, WalkSettingsView, WalkPlanContent, RoutePreviewContent, PlaceDetailContent, DemoMapView/LiveMapView, ItineraryComponents, RemoteArtwork, SeruTheme and new motion/photo helpers.
- [ ] Integrate snapshots/journal and visible current conditions, New Walk, dynamic duration picker and 44pt actions.
- [ ] Remove route-save controls; add plan editing/return information and capable map/share links.
- [ ] Replace raster map presentation with native MapKit + local POIs, consistent fixture naming and origin labels.
- [ ] Move photo normalization off MainActor; add text copy/photo zoom and robust announcements.
- [ ] Apply restrained shared motion and fix large-text menu symbols, dark layers and duplicate actions.

## Task 6: Integrate, verify and checkpoint (root)
- [ ] Regenerate Xcode project after source changes.
- [ ] Run full swift test, iOS build and updated focused UI flows in Simulator.
- [ ] Inspect fresh light/dark/large-text/splash/history/plan screenshots, obtain independent review and resolve issues.
- [ ] Update README, completion ledger and recovery instructions. Keep backup tag intact; commit tested improvements in this repository.
