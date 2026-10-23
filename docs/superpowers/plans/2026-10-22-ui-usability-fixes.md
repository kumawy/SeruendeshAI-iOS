# UI usability fixes implementation plan

> For agentic workers: use subagent-driven-development for the independent saved-events and chat tasks; verify the integrated app in iPhone Simulator.

**Goal:** Fix the reviewed UI issues except the icon-only bottom tabs, which the user explicitly wants preserved.

**Architecture:** Keep the existing SwiftUI views, AppModel, palette, native tab bar, and server API. Share locally saved event state through AppModel so Events and Saved render the same bookmarks. Reuse event cards and details rather than creating another presentation.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, XCTest UI tests, iOS 26+, XcodeGen.

**Spec:** The preceding UI review and the user's instruction, “исправь все кроме 3”.

## Global constraints

- Preserve the bottom tab bar as icons only; do not modify AppRootView labels.
- Preserve current conversation, draft, attachment, filters, and plan when leaving empty Saved via “Найти места”.
- Saved must include “Места”, “Маршруты”, and “События”; event bookmarks are shared with Events and survive relaunch.
- Preserve existing event bookmark IDs under `seruendesh.savedEventIDs`; save snapshots so bookmarked events remain available when outside the current feed.
- Use local storage for event bookmarks; do not invent a server synchronization API.
- The photo and text of an event card open the same details; its heart remains an independent save control.
- Collection controls must support the largest accessibility text size without breaking words or clipping labels.
- Empty expanded chat offers three suggestions that fill the composer and permit editing; do not send automatically or overwrite an existing draft/attachment.
- Keep current colors, typography, native affordances, and light/dark appearance.

## Review focus

- Existing event IDs must migrate without losing bookmarks, including events loaded by a later feed refresh.
- Saving/removing an event on either tab must update the other immediately and remain correct after relaunch.
- Empty-state navigation must not discard chat or an attachment in progress.
- Suggestions must disappear for active conversations and not introduce extra composers or displace quick filters.
- Verify collection selection, event cards, and chat with accessibility Dynamic Type as well as ordinary text.

## Task 1: Saved navigation, event bookmarks, and adaptive collections

**Files:** AppModel.swift, EventsView.swift, SavedView.swift, focused existing/new Tests files.

- [x] Add regression tests for bookmark persistence/migration and snapshots surviving feed changes; observe the failing baseline.
- [x] Move event bookmark ownership from EventsView's AppStorage into AppModel using the existing IDs key; expose savedEvents, isEventSaved, and toggleSavedEvent.
- [x] Share event card/detail views with Saved, and make the event photo open details without nesting the save button inside a link.
- [x] Add Events to Saved with its own useful empty state; ordinary empty-state navigation changes the selected tab only.
- [x] Adapt collection selection to vertical full-width options at accessibility sizes and a fitting/scrolling layout otherwise.
- [x] Run focused Swift tests and report changed files and validation to root.

## Task 2: Empty chat suggestions

**Files:** ChatScreen.swift only; root owns UI tests.

- [x] Add “Погулять час рядом”, “Прогулка у реки”, and “Кофе по пути” to the empty expanded conversation.
- [x] Expose `chat-suggestion-nearby`, `chat-suggestion-river`, and `chat-suggestion-coffee` for UI testing.
- [x] Fill the bound draft and focus editing; never submit, replace a nonempty draft, or interfere with an attachment.
- [x] Preserve compact panel height, anchored composer, existing quick-filter placement, Reduce Motion, and large-text scrolling.

## Task 3: Integration and verification

**Files:** UITests/SeruendeshAIUITests.swift (root), generated Xcode project only if required for new source membership.

- [x] Add UI regressions for empty-state navigation preserving a conversation/draft, event photo navigation and shared favorites, and suggestions filling without sending.
- [x] Run the new UI scenarios against the original UI first where practical, then against the changes.
- [x] Run swift test and the relevant iOS UI test suite; build the iOS app.
- [x] Inspect ordinary light/dark renders and the largest Dynamic Type size in Simulator.
- [x] Obtain independent review, resolve material findings, and report verified results.

## Workspace notes

This directory has no Git repository. Work directly in the authorized workspace, preserve a temporary pre-change snapshot for diff review, and do not initialize Git or create commits.

## Verification results

- `swift test`: 98 tests in 9 suites passed.
- iOS unit tests: 110 tests in 12 suites passed.
- Existing and new UI flow suite: 8 tests passed.
- Largest Dynamic Type selection and suggestion scenario: 1 test passed.
- Inspected light/dark chat, ordinary Saved, and largest-text Saved/chat screenshots from XCTest attachments.
- Independent review found no material issues; AppRootView is byte-for-byte unchanged.
- SourceKit indexing completed successfully.
