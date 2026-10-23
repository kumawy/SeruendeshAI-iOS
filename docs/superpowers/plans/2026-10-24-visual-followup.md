# Visual follow-up: events, profile and route

Requested from the user's screenshots after the first UX implementation.

Direction: retain the forest palette and native type; reduce toolbar noise, replace oversized Form groups with a deliberate profile layout, and make the itinerary the primary reading order.

- Events: provider badge at the photo's top right and branded Sxodim/Ticketon outbound action, replacing calendar export. Exact event URLs when supplied; explicitly labelled city-listing fallback for local examples.
- Profile: compact identity, editable name, Journal, theme and existing account actions; one shared profile button across tabs.
- Plan: opaque full-page surface, concise duration/distance, inline map, numbered stops, return warning without repeated paragraphs, edit and map actions.
- Map: numbered stop annotations, distinct start, contrast casing, honest estimated dashes. No base-map bleed beneath the lower navigation area.
- Chat: labelled Journal/Plan shortcuts, move New Walk into the menu, compact conditions row.

Verification: Core tests for source resolution, existing state/history coverage, simulator journeys for provider detail, profile editing/theme, itinerary editing/full route, screenshots in light/dark and accessibility type. Preserve the one-second splash pacing. Commit and push to the existing private pet_project main; no new branches.

Completed:169 SwiftPackage tests,185 iOS unit tests and11 distinct UI journeys passed across focused runs. Three final map checks passed again after adjusting short-route camera framing and moving the estimated-path caption below the native attribution. Latest iOS simulator build passed. Screenshots inspected in light/dark and accessibility XXXL.

Provider references: [Sxodim Astana](https://sxodim.com/astana), [Ticketon Astana](https://ticketon.kz/astana). Sxodim red is deepened slightly for white-text contrast; Ticketon uses its current green with dark text. Local fixture links explicitly open a city listing.
