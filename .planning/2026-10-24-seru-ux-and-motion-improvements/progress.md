# Progress

2026-10-24: Backed up complete source to new private kumawy/pet_project before any app edits. Tagged and verified remote SHA. Read relevant planning/design/SwiftUI/TDD skills. Wrote authorized design and six-task plan. Starting parallel owned implementation.

- Core worker: 149 tests /14 suites passed, context/history/planning/retry complete. Root cache RED (3 tests failed for missing persistence) then GREEN (all26AccountStoreTests pass).
- Event worker first pass complete,16event regressions; calendar reviewed export and transactionaldates.
- Fast splash source integrated; spiral/Metal/frame-player launch files removed. Chat/photo and map/plan integration in progress.
- Root added Journal/Profile entry points, account cache UI distinctions, Favorites Undo and dark surface hierarchy.
- Independent correctness review running.

- Independent review found and corrected: stale geocoded origin on Journal restore; New Walk retaining an interrupted retry; inactive Retry after process restart; unverified-cache refresh bypass; sequential filter edits clearing cancellation feedback; missing supplied facts in account snapshot; stale local Favorites ETA; wrong-city venue search and live snapshot origin label. Regressions were observed RED before fixes.
- First iOS app build passed. First simulator pass: Journal archive/restore/relaunch and event/profile/date-cancel flows passed; exposed New Walk staying on Favorites (fixed) and legacy test assumptions for native MapKit/new persistent Journal (updated). Largest-text inspection led to compact Journal icon in accessibility sizes.
- Fresh Swift core suite:163 tests /15 suites passed after review fixes. Splash now uses absolute presentation deadlines to prevent accumulated scheduling delay.
- Second integrated iOS unit/UI run in progress; includes stop deletion editor, Journal, Undo, events, 8 splash cases, local end-to-end discovery and largest text.

## Final verification
- Latest source builds successfully for iPhone17Pro/iOS26.5, log `.build/ux-build-verified.log`.
-164 SwiftPackage tests /15 suites PASS (`.build/ux-core-verified.log`);180 iOS unit tests /18 suites PASS (`.build/ux-ui-verified.log`).
-14 distinct UI cases PASS across focused runs: complete local discovery; all8 splash cases; largest text; Journal archive/restore/relaunch/visual margins; Favorites Undo/Profile/Journal; stop editor deletion; Events/Profile/date cancel/no bookmarks/calendar editor cancel. Bundles: `.build/ux-refinement-second.xcresult`, `.build/ux-refinement-final.xcresult`, `.build/ux-chat-layout.xcresult`.
- Late fixes verified: LazyVStack no longer lays out the empty welcome; unnecessary scrollTargetLayout caused restored-card horizontal displacement and was removed; native stop deletion image was replaced by an explicit accessible44pt action; edited plans without messages are archived in Journal.
- Inspected native map in both themes, largest-text welcome, calendar editor, stop editor and final restored chat screenshot. No temporary diagnostics remain.
- Live-account lifecycle tests intentionally not run: they create/delete real accounts. All networked unit coverage uses stubs. Physical-device testing was not part of this run.
- New/private GitHub baseline tag remains unchanged; tested improvement checkpoint will be committed to main.

## Splash pacing follow-up
- User found0.52s too abrupt. Normal greeting now0.75s plus0.25s fade (1.0s total). Reduced Motion stays0.14s; no other launch behavior changed.
- Updated lower/upper pacing regression: old0.52s observed RED; all13 splash core tests GREEN. Two targeted iOS launch/ReduceMotion UI tests PASS; build and whitespace check pass. Read-only independent review found no timing coupling issues.

## Visual follow-up from screenshots
- Replaced event calendar actions with branded provider links/badges. Official city listings are used for local examples; supplied real event URLs retain their destination. Five source-resolution regressions added.
- Rebuilt Profile, shared profile buttons and compact chat toolbar. Plan is now an opaque full-page itinerary with inline map; map stops use numbers and a distinct start.
- First integration:169 SwiftPackage tests /16 suites and185 iOS unit tests /19 suites passed. UI verification exposed inherited accessibility IDs in the theme selector and outdated smoke-test expectations; fixed. Added larger-text handling for map controls, initials and stop rows.
- Final verification PASS:169 SwiftPackage tests /16 suites,185 iOS unit tests /19 suites,11 distinct UI journeys across `.build/visual-followup-2.xcresult` and `.build/visual-followup-3.xcresult`. Final map refinement additionally passed all3 route UI cases in `.build/visual-map-final.xcresult`; latest app build passed (`.build/visual-final-build.log`).
- Visual QA in light/dark and accessibility XXXL found and fixed short-route pin overlap and a legend covering the native map attribution. Final map screenshots are in `.build/visual-map-final-captures`; independent review found no remaining actionable issues in scope.
- Latest app installed and launched on the main iPhone17Pro simulator; temporary profile-test name removed. Existing private pet_project/main remains the only remote/branch; baseline recovery tag unchanged.

## City-guide redesign
- User rejected the repeated green-card appearance and approved a neutral native city-guide direction. Added PRODUCT.md and source-matched DESIGN.md / .impeccable/design.json.
- Replaced green grounds with charcoal/paper, flattened Events/Saved/Profile/Chat, restored native tab labels and theme segmentation. Plan and map now share one adjustable workspace; returning from a stop preserves the chosen list mode.
- Replaced ten bundled images with real photography (seven place images and three thematic event illustrations). Corrected the Botanical Garden photo mismatch; reachable Profile photo credits contain all eight author/source/license entries.
-169 SwiftPackage tests and185 iOS unit tests passed. Thirteen distinct UI cases passed in city-guide-main/design/final-visual/dark-review; latest AX plan check passed again after compact header controls and hiding map controls beneath expanded content.
- Visual inspection caught a profile sheet that did not repaint on live theme changes: fixed local presentation preference and added actual colour-scheme assertions. Fresh Profile tests passed in regular/AX text.
- Fresh independent visual reviewer inspected nine screenshots and requested one material fix: empty Events search placeholder contrast. Explicit semantic muted prompt implemented. Both-theme journeys passed; the reviewer measured6.89:1 dark /5.17:1 light, scored the fix resolved and returned ship for the verdict pass.
- Final evidence:169 SwiftPackage tests,185 iOS unit tests and14 distinct UI journeys passed across focused runs. Latest app compiled in `.build/city-guide-contrast-final.xcresult`. Native phone screenshots are retained locally in `.impeccable/review`; source-matched design tokens and photo attribution are committed as project documentation.

## Profile and splash restoration
- User requested removing “Фотографии” from Profile and restoring the original splash without its spiral. Removed the row and its unused sheet; bundled photo attribution and JPEG metadata remain.
- Restored the full one-shot mascot greeting with the existing bounded APNG player, at the original visible size:1.8s greeting and a direct0.25s fade. This supersedes the one-second static greeting above. Kept the0.14s static Reduce Motion path, mounted root, session gate and background cancellation.
- Updated pacing checks first and observed the shortened greeting fail. Final verification:169 SwiftPackage tests,185 iOS unit tests and all11 selected UI cases passed (8 splash,3 profile), `.build/splash-restore.xcresult`.
- Inspected a fresh native launch recording in `.impeccable/review/splash-restored.mp4`. Independent review confirmed the full gesture settles before the direct crossfade, with no cut, size jump or spiral. Latest build installed on the main iPhone17Pro simulator.
