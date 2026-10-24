# City Guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the user's accepted eight proposals to replace the repetitive green-card look with a credible native city guide.

**Architecture:** Preserve Core state and persistence. Redesign feature compositions around the existing SwiftUI/MapKit interfaces; merge plan/map presentation in WalkView rather than duplicate route navigation.

**Tech Stack:** Swift6, SwiftUI iOS26, MapKit, XCTest, Swift Testing.

**Spec:** PRODUCT.md, DESIGN.md and the eight accepted proposals in this conversation.

## Global Constraints
- Default local data, photos, Journal and favorites remain functional.
- Keep Sxodim/Ticketon branded actions/badges, no calendar or event/route save actions.
- Keep mascot, one-second splash, Reduce Motion and44pt controls.
- Existing private pet_project/main only. Root integrates and commits.

## Review Focus
- Long names and accessibility XXXL: controls readable, all actions scroll clear of navigation.
- Plan edits and empty plans: keep editor/retry/Journal behavior after merging map and list.
- Returning from a stop or other tab: preserve conversation and useful map/list context.
- Local estimates: disclose approximation and return-time limits without burying warnings.
- Photography: correct named places, compatible licenses and reachable credits.

### Task1: Shared visual language and secondary surfaces (root)
- [x] Update SeruTheme.swift neutral tokens, typography/radii and native tab labels in AppRootView.swift.
- [x] Flatten ChatScreen.swift and SavedView.swift compositions, keep existing actions/IDs.
- [x] Verify chat restoration, saved Undo, both themes and accessibility layout with existing UI journeys.

### Task2: Events and Profile (independent workers)
- [x] EventsView.swift: photo-led editorial rows, compact provider actions, fewer containers; preserve all filtering and provider semantics.
- [x] ProfileView.swift: small identity, plain Journal/account rows, segmented theme selector with AX fallback; adapt ProfilePolishUITests.swift.
- [x] Root supplies PhotoCreditsView() reading Resources/PhotoCredits.json.
- [x] Verify provider detail, date cancellation, name/theme persistence and large text. Corrected live theme changes in the already-presented profile sheet.

### Task3: Unified walk workspace (root)
- [x] WalkView.swift: .plan uses map behind the adjustable panel; route/map button changes detent without pushing a duplicate route.
- [x] WalkPlanContent.swift: remove nested mini-map and duplicate map CTA; keep stop editing, audio, share, return warning and external directions.
- [x] Update RouteDesignUITests.swift to assert one workspace, map/list expansion, editor and back behavior, including preserving expanded stops after a place detail.

### Task4: Credible photography (independent worker)
- [x] Inspect active assets; replace mismatched/generated-looking place pictures with verified real-place photos. Replaced three event covers with actual thematic photographs, explicitly credited as illustrations for local examples.
- [x] Record source, author, license and assets in Resources/PhotoCredits.json and docs/photography-sources.md.

### Task5: Integrate, review and save (root + fresh reviewer)
- [x] Generate Xcode project, run Core and affected UI checks, inspect screenshots in both themes and accessibility XXXL.169 SwiftPackage tests,185 iOS unit tests and14 distinct UI cases passed across focused runs.
- [x] Batch visual corrections, independently review final screenshots and record design tokens. Reviewer found one contrast issue; both-theme recapture scored it resolved (ship verdict).
- [x] Prepare final checkpoint for existing private main, with verified remote scope and latest simulator app. Commit/push confirmation is recorded in the delivery message and Git history.
