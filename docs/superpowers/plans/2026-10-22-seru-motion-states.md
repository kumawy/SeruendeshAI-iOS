# Seru Motion States Implementation Plan

> For agentic workers: use subagent-driven-development; implement continuously within user-approved scope.

**Goal:** Ship the15 approved animated mascot states in the existing Seru app with real assets and previews.
**Architecture:** Shared scene catalog + bounded native player; Remotion generates reusable prop-based scenes; existing views select semantic states; AppModel emits small Foundation-only success/photo-error feedback.
**Tech Stack:** Swift6 strict concurrency, SwiftUI/iOS26, ImageIO, Remotion4.0.537, React19, image_gen.
**Spec:** docs/superpowers/specs/2026-10-22-seru-motion-states.md

## Global Constraints
- Preserve current project/design/themes/navigation/business behavior. Direct user project is not a Git repository; use task backups instead of worktree/commits.
- Loop only while visible/active; poster for Reduce Motion; bounded memory and compact runtime assets.
- All15 situations must map to real app conditions; common scenes may be reused.
- Keep error text, cancellation/retry and actual data status honest; no fake GPS/progress/sync completion.
- Generated art, Remotion sources and rendered files saved to workspace outputs/seru-state-pack.

## Review Focus
- Fast requests and cancellation: no delayed mascot result can outlive its request.
- Switching tabs, scrolling, covering sheets and Reduce Motion: no stale background loops.
- Existing conversations/photo drafts: stable composer identity, attachments survive panel changes.
- Account and guest saves: feedback does not change persistence/sync semantics.
- Empty events: filter emptiness vs selected-day emptiness vs load failure remain distinct and recoverable.

## Tasks
- [x] Shared catalog/player: DesignSystem/SeruMascotAnimation.swift, adapt Features/SavedMascotAnimation.swift wrapper. Verify APNG frame decoding/loop using existing box; keep PNG compatibility. Add meaningful decoder/catalog tests.
- [x] Assets: nine new character key artworks, shared deterministic Remotion project and14 scene exports (including reused box/wave); inspect contact sheets/alpha, motion, clean endpoints and export metadata. Compact native APNG runtime assets + posters.
- [x] Chat/walk/route/photo: ChatScreen.swift, ChatComposer.swift, WalkView.swift, WalkPlanContent.swift, RoutePreviewContent.swift, Core/AppModel.swift, Core/MascotFeedback.swift, ChatAttachmentLoader.swift. Hook greeting/thinking/noPlaces/routing/routeBlocked/photoLoading/photoError/ready/saved. Keep controls and accessible IDs.
- [x] Events + feedback: EventsView.swift state routing for calendar/search/saved-empty/loading/failure; AppRootView.swift nonblocking reaction overlay; resource project.yml and xcodegen registration.
- [x] Review/test: source review, current unit tests, mock-backed native UI scenarios for all state families including loop/once/Reduce Motion, cancellation/retry, filters/saves/photo errors, AX type and themes. Render and inspect actual native captures. No completion claim from zero-test success.
- [x] Delivery: gallery/contact sheet, per-scene MP4/GIF/alpha masters, Remotion source ZIP, changed-file manifest/backups and exact validation report. Mark ledger complete only after all15 mappings verified.

## Completion evidence

All14 scenes rendered and integrated for15 cases. Swift Package116pass; final native run15pass/0fail (7decoder+8UI); two additional box loop/ReduceMotion UI cases pass. All1421runtime alpha frames exact in native production store, cache<=5. Full report and file inventory: workspace outputs/seru-state-pack/RESULT.md. Physical iPhone energy/FPS measurements remain outside this simulator/Mac validation.
