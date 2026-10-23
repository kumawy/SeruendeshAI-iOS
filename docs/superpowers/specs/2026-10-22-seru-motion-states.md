# Seru motion states

User approved implementing all15 situations from the immediately preceding proposal, in the existing native app, with real Remotion animation files and reviewable previews. Preserve themes, navigation, data behavior, cancellation/retry, accessibility and existing mascot identity.

Mapping (scene enum raw names):
1 Empty saved places: emptyBox (existing).
2 No events on selected date: calendarEmpty.
3 Event search/filter no results: searchEmpty.
4 No saved events under saved-only filter: emptyBox reuse.
5 Events loading: postersLoading.
6 Empty expanded chat greeting: greeting (existing wave source reused, once).
7 Recommendation pending: thinking.
8 No matching places: noPlaces.
9 Route/plan pending: routing.
10 Route/plan unavailable: routeBlocked.
11 Photo transfer/preparation: photoLoading.
12 Photo load/open/size error: photoError (short feedback).
13 Network/server data load error: connectionError, preserving specific error text/retry.
14 Place/event saved: saved (short once reaction).
15 Recommendation/route/plan ready: ready (short once reaction).

New unique key artworks: calendar, magnifier, posters, map (thinking/routing/ready), compass, blocked-map, photo (loading/error), phone, save-heart. Original wave and empty box reused. New artworks use image_gen with original mascot identity. Remotion drives deterministic local prop/wing/head deformation, distinct timing/expressions and clean loop endpoints; no single whole-image wobble as substitute for interaction. Working master videos, alpha source sequences and a gallery are deliverables.

Native scene API: SeruMascotAnimation(scene: SeruMascotScene, isActive: Bool=true), caller owns sizing. Catalog scenes exactly as mapping above. Playback loops except greeting/saved/ready, which play once and settle. Respect Reduce Motion with poster; stop when tab/scene/viewport is hidden. Test compatibility flag -seru.emptyBox.reduceMotion remains supported. Use bounded decoding and compact runtime assets; evaluate ImageIO/APNG against existing box before committing new animation formats. Resource folder SeruMotion/<sceneRawValue>/{animation.png,poster.png,manifest.json}; source archives contain reproducible Remotion assets, not node_modules. Missing/bad resources must safely show a still.

Feedback model must stay Foundation-only in Core for existing Swift package tests: MascotFeedback { UUID id, Kind kind(saved/ready/photoError), String message }; AppModel owns optional mascotFeedback. UI maps kinds to scenes. Feedback is nonblocking, brief, and does not delay results or falsely report server synchronization complete.

Events must distinguish saved-only empty, query/category/price-filter empty, and no events on selected date. Keep existing controls, detail/bookmarks, retry, refresh, and real error messages. No new fake GPS/arrival states or standalone demo as product replacement.
