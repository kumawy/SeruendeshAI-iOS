---
name: Seru city guide
description: A quiet native guide to places, walks and events in Astana.
colors:
  background-light: "#F7F5F0"
  background-dark: "#161717"
  surface-light: "#FFFFFF"
  surface-dark: "#1D1E1E"
  field-light: "#EDEAE5"
  field-dark: "#282929"
  assistant-bubble-light: "#F7F5F0"
  assistant-bubble-dark: "#1D1E1E"
  forest: "#23583F"
  action-light: "#23583F"
  action-dark: "#A5C4B3"
  on-action-light: "#FFFFFF"
  on-action-dark: "#161717"
  lime-light: "#E5EDE5"
  lime-dark: "#303B35"
  ink-light: "#202322"
  ink-dark: "#F2F1ED"
  muted-light: "#5E625F"
  muted-dark: "#B0B3AF"
  line-light: "#DDDAD3"
  line-dark: "#393B3A"
  provider-sxodim: "#D83525"
  provider-ticketon: "#4EBC73"
  on-provider-ticketon: "#102718"
typography:
  display:
    fontFamily: "System (San Francisco)"
    fontSize: "SwiftUI .largeTitle"
    fontWeight: 600
  headline:
    fontFamily: "System (San Francisco)"
    fontSize: "SwiftUI .title"
    fontWeight: 600
  title:
    fontFamily: "System (San Francisco)"
    fontSize: "SwiftUI .title2"
    fontWeight: 600
  title-compact:
    fontFamily: "System (San Francisco)"
    fontSize: "SwiftUI .title3"
    fontWeight: 600
  body:
    fontFamily: "System (San Francisco)"
    fontSize: "SwiftUI .body"
    fontWeight: 400
  body-medium:
    fontFamily: "System (San Francisco)"
    fontSize: "SwiftUI .body"
    fontWeight: 500
  action:
    fontFamily: "System (San Francisco)"
    fontSize: "SwiftUI .body"
    fontWeight: 600
  subheadline:
    fontFamily: "System (San Francisco)"
    fontSize: "SwiftUI .subheadline"
    fontWeight: 400
  subheadline-action:
    fontFamily: "System (San Francisco)"
    fontSize: "SwiftUI .subheadline"
    fontWeight: 600
  footnote:
    fontFamily: "System (San Francisco)"
    fontSize: "SwiftUI .footnote"
    fontWeight: 400
  label:
    fontFamily: "System (San Francisco)"
    fontSize: "SwiftUI .caption"
    fontWeight: 500
  caption:
    fontFamily: "System (San Francisco)"
    fontSize: "SwiftUI .caption"
    fontWeight: 400
rounded:
  compact: "8pt"
  attachment: "10pt"
  action-photo: "12pt"
  thumbnail: "14pt"
  message: "16pt"
  card: "20pt"
  panel: "24pt"
  composer: "28pt"
spacing:
  tight: "4pt"
  related: "8pt"
  content: "12pt"
  feed-gutter: "16pt"
  walk-gutter: "20pt"
  profile-gutter: "24pt"
  section: "32pt"
  profile-section: "36pt"
components:
  button-primary-light:
    backgroundColor: "{colors.action-light}"
    textColor: "{colors.on-action-light}"
    typography: "{typography.action}"
    rounded: "{rounded.action-photo}"
    padding: "10pt 12pt"
  button-primary-dark:
    backgroundColor: "{colors.action-dark}"
    textColor: "{colors.on-action-dark}"
    typography: "{typography.action}"
    rounded: "{rounded.action-photo}"
    padding: "10pt 12pt"
  card-light:
    backgroundColor: "{colors.surface-light}"
    rounded: "{rounded.card}"
  card-dark:
    backgroundColor: "{colors.surface-dark}"
    rounded: "{rounded.card}"
  input-composer-light:
    backgroundColor: "{colors.field-light}"
    textColor: "{colors.ink-light}"
    typography: "{typography.subheadline}"
    rounded: "{rounded.composer}"
    padding: "6pt"
  input-composer-dark:
    backgroundColor: "{colors.field-dark}"
    textColor: "{colors.ink-dark}"
    typography: "{typography.subheadline}"
    rounded: "{rounded.composer}"
    padding: "6pt"
  filter-light:
    backgroundColor: "{colors.field-light}"
    textColor: "{colors.ink-light}"
    typography: "{typography.subheadline}"
    rounded: "{rounded.compact}"
    padding: "0pt 14pt"
  filter-selected-light:
    backgroundColor: "{colors.ink-light}"
    textColor: "{colors.background-light}"
    typography: "{typography.subheadline-action}"
    rounded: "{rounded.compact}"
    padding: "0pt 14pt"
  filter-dark:
    backgroundColor: "{colors.field-dark}"
    textColor: "{colors.ink-dark}"
    typography: "{typography.subheadline}"
    rounded: "{rounded.compact}"
    padding: "0pt 14pt"
  filter-selected-dark:
    backgroundColor: "{colors.ink-dark}"
    textColor: "{colors.background-dark}"
    typography: "{typography.subheadline-action}"
    rounded: "{rounded.compact}"
    padding: "0pt 14pt"
  provider-sxodim:
    backgroundColor: "{colors.provider-sxodim}"
    textColor: "{colors.on-action-light}"
    typography: "{typography.subheadline-action}"
    rounded: "{rounded.compact}"
    padding: "10pt 14pt"
  provider-ticketon:
    backgroundColor: "{colors.provider-ticketon}"
    textColor: "{colors.on-provider-ticketon}"
    typography: "{typography.subheadline-action}"
    rounded: "{rounded.compact}"
    padding: "10pt 14pt"
---

# Design System: Seru city guide

## Overview

**Creative North Star: "A quiet city guide"**

Real places, useful maps and readable information lead Seru. Warm white and charcoal grounds keep the interface calm; green directs an action or marks a meaningful state. The approved mascot carries the conversational personality through greetings, loading, feedback and empty states.

This is a native iOS 26 SwiftUI system. Photographs provide the strongest visual expression. Ordinary information uses spacing, typography and fine separators; containers serve fields, messages, overlays and genuine groups. Motion explains a change of state and remains optional under Reduce Motion.

**Key Characteristics:**

- Neutral grounds with a restrained forest action accent.
- Real place and event photography with visible source context.
- Native typography, navigation, theme selection and accessible controls.
- One persistent walk workspace for the map, conversation and stops.
- A preserved mascot with short, state-driven motion.

This document records the implemented system. Color primitives come from `SeruendeshAI/DesignSystem/SeruTheme.swift`; provider colors come from `Features/EventsView.swift`. Frontmatter values are normative. `-light` and `-dark` identify the two values of each adaptive `SeruColor` role. Spacing and radii use native points. Typography values name SwiftUI Dynamic Type styles rather than CSS sizes. Native platform controls retain their system metrics.

## Colors

The palette pairs warm paper and charcoal with forest and pale sage for actions.

### Primary

- **Action forest / action sage:** `action-light` / `action-dark`, used with their matching `on-action` foreground for principal actions, active tabs, route controls and selection indicators.
- **Forest:** the fixed `forest` role, retained where the identity requires a stable green; prefer the adaptive `action` role for interactive controls.
- **Soft green:** the legacy-named `lime` role, used as a quiet highlight in `TagPill`; this is a supporting state tint.

### Neutral

- **Warm paper / charcoal:** the adaptive `background` role for page grounds.
- **White / raised charcoal:** `surface` for panels, sheets and purposeful groups. `assistantBubble` remains an available theme role; current assistant prose is drawn directly on its conversation surface.
- **Warm field / dark field:** `field` for inputs, neutral chips and user messages.
- **Ink:** `ink` for primary information; **muted ink:** `muted` for supporting information; **fine line:** `line` for borders and separators.

### Provider and semantic colors

Sxodim uses `provider-sxodim` with white text. Ticketon uses `provider-ticketon` with `on-provider-ticketon`. These colors identify an external destination. Native semantic red marks a saved heart, errors and destructive account actions; it is not a new brand accent. Native map rendering and map-specific route ink remain owned by the map implementation.

**The Action Accent Rule.** Use the adaptive action green for app actions, active navigation and route state. Ordinary text and page surfaces remain neutral; provider branding and semantic red retain their own roles.

## Typography

**Display and body font:** native system San Francisco through SwiftUI `.system` and semantic text styles. There is no bundled custom typeface or separate display family.

### Hierarchy

- **Display:** `.largeTitle`, semibold; Events and Saved page titles.
- **Headline:** `.title`, semibold; event detail titles. Place detail uses the native bold variant.
- **Title:** `.title2`, semibold; section headings and walk/route headings.
- **Compact title:** `.title3`, semibold; event feed titles, profile identity and empty-state titles.
- **Body:** `.body`, regular; readable assistant messages and account rows. Medium identifies place/recommendation titles; semibold identifies principal actions.
- **Supporting text:** `.subheadline`, regular; venue, secondary information and composer text. Medium or semibold is used for an action or selected filter.
- **Small text:** `.footnote` and `.caption`; context, credits and metadata. `TagPill` uses medium caption text. Caption semibold appears in price badges and compact metrics.

The chat message text adds native line spacing (4 pt). Content may wrap vertically. Decorative SF Symbols and map stop numerals may use local fixed-size metrics; they do not replace scalable reading text.

**The Native Type Rule.** Use SwiftUI text styles for reading and actions so Dynamic Type can change their metrics. Do not freeze semantic text styles into fixed point sizes.

## Layout

Walks, Events and Saved use the native three-tab navigation. The walk view keeps the map mounted beneath a single draggable panel; conversation, results, place details and ordered stops occupy that workspace. Compact, medium and expanded states change the visible area without creating a second full-route screen.

Use the observed per-surface gutters: Events and Saved (16 pt), walk plans and route previews (20 pt), Profile (24 pt). Local related groups usually use 8–12 pt; section separation uses the larger observed spacing steps. Profile uses 36 pt between its main groups and caps content width at 560 pt. Do not impose a new app-wide width breakpoint.

Allow content-driven adaptation: `ViewThatFits`, wrapping labels and alternate vertical arrangements keep information visible. Profile's segmented theme picker becomes full-width option rows at accessibility text sizes. Saved-place metadata and actions can stack; event photo badges stack at accessibility sizes. All interactive targets are at least 44 pt; principal actions have a minimum height of 50 pt.

## Elevation & Depth

The system is predominantly flat. Neutral tones and fine lines distinguish content; photographs add visual depth. Shared `seruCard` surfaces have no shadow. Native materials remain on map controls, the header fade and transient toast. The mascot feedback banner has a soft black shadow (opacity 0.08, radius 16 pt, vertical offset 6 pt); compact map annotations use small readability shadows over map artwork. These overlays do not establish a shadow style for ordinary rows.

**The Quiet Surface Rule.** Separate ordinary rows through spacing and fine dividers. Add a surface only when it communicates a field, message, overlay or distinct group.

State changes use `SeruMotion`: panel spring (response 0.3 s, damping 0.9), scroll ease-out (0.18 s), feedback ease-out (0.18 s; 0.12 s under Reduce Motion). `SeruPressStyle` lowers opacity to 0.86 and scales to 0.985 over 0.14 s while pressed; Reduce Motion removes its scale and animation. Event filter selection uses a short ease-out (0.16 s) when motion is allowed. Avoid repeated row entrances.

The standard splash plays the full mascot wave (1.8 s), then reveals the mounted app through a circle expanding from the screen center to every corner (0.55 s, ease-in-out). No spiral. Its Reduce Motion path uses a static mascot, short hold (0.02 s) and opacity fade (0.12 s), without the circular motion. Do not extend the splash to wait for account restoration, network data or artwork.

## Shapes

Use softly rounded rectangles with a clear purpose. The shared `seruCard()` default remains **20 pt**, with no automatic padding or border. It is an available grouped surface, not the default wrapper for lists.

Compact event filters, provider actions and Saved thumbnails use 8 pt corners. Attachments and small stop photos use 10 pt. Primary actions and event/recommendation photos use 12 pt. The shared `PlaceThumbnail` uses 14 pt; user messages and place detail photos use 16 pt. The walk panel rounds only its upper corners at 24 pt; the composer uses 28 pt. Capsules remain appropriate for metadata and circular shapes for avatar, save/send and map controls. These distinct values are intentional component defaults, not one universal radius.

## Components

### Buttons

`PrimaryAction` is a full-width adaptive green action with matching foreground, body semibold text, 12 pt corners, vertical padding 10 pt, horizontal padding 12 pt and minimum height 50 pt. Its optional symbol is omitted at accessibility text sizes. It uses `SeruPressStyle`.

Secondary actions are plain text or SF Symbol controls with a minimum 44 pt target. `ProfileButton` is a quiet person symbol. `SavePlaceButton` exposes its saved state and VoiceOver action; native semantic red marks the filled heart. Disabled and in-progress controls keep their existing behavioral states.

### Chips

`TagPill` is noninteractive caption metadata with capsule geometry and horizontal/vertical padding 11/7 pt. A highlighted pill uses `lime` at opacity 0.45. It is not automatically a 44 pt control.

`EventFilterPill` is an interactive rounded rectangle with 8 pt corners, horizontal padding 14 pt and minimum height 44 pt. Unselected filters use `field` and `ink`; selection reverses `ink` and `background`, changes the type weight and adds the selected accessibility trait. Selection does not require green.

### Cards / Containers

`seruCard` supplies only a surface and default 20 pt radius. Events, Saved rows, profile account rows and stop lists are visually separated without a surrounding card. A chat recommendation leads with a photograph and follows with readable title/context and a simple “На карту” action.

Event feed photography is 224 pt high with 12 pt corners. Quiet title/date/venue information follows it; the compact provider action preserves Sxodim or Ticketon identity, 8 pt corners, horizontal/vertical padding 14/10 pt and minimum height 44 pt. Price and provider badges use capsules. Local examples must retain their honest listing destinations.

### Inputs / Fields

`ChatComposer` uses the neutral `field` ground, 28 pt corners and 6 pt outer padding. The body of its text field uses `.subheadline`; attachment, filter and circular send controls provide 44 pt targets. The send control uses `action` and `onAction`, with the current disabled opacity 0.5. The input allows multiple lines and adapts its line count to accessibility size and focus.

The Events search field uses `field`, 12 pt corners and minimum height 52 pt. Keep native focus, keyboard, submission and dismissal behavior; do not add a decorative focus glow.

### Navigation

Use native `TabView`, `NavigationStack`, sheets and toolbars, tinted with adaptive `action`. The profile is a plain identity and grouped rows with fine separators. Theme selection uses the native large segmented picker for Auto/Light/Dark, then checkmarked rows at accessibility sizes. A close symbol or native confirmation item dismisses sheets.

### Walk workspace and mascot

The map and stop list are two views of one walk. Keep ordered stops, route estimates and map annotations in sync. Estimated geometry remains dashed and labelled approximate; native map controls keep their standard semantics.

Preserve the supplied Seru mascot assets and scene-specific playback. Greetings, photo loading, saved/ready feedback and empty states carry the personality; the interface does not need extra green panels to reinforce it. Pause inactive/offscreen playback and respect Reduce Motion. Keep local data, photo attachments, restoration and Journal behavior intact when changing presentation.

## Do's and Don'ts

### Do:

- Do use adaptive SeruColor roles and the existing SwiftUI text styles.
- Do lead place and event content with relevant photographs and preserve photo credits and provider identity.
- Do use plain rows and fine dividers for account, saved-place and stop information.
- Do keep controls at least 44 pt, expose VoiceOver actions and let accessibility text reflow.
- Do keep the map and ordered stops in one walk workspace and preserve approximate-route labels.
- Do preserve mascot assets, local-data behavior and the full greeting with a circular reveal.

### Don't:

- Don't spread green across ordinary page sections or recolor provider links as app actions.
- Don't wrap every row in a card or add decorative gradients and shadows.
- Don't replace native theme selection, sheets or tab navigation with custom ornamental controls.
- Don't repeat entrance animations on rows or require spatial motion to understand a state.
- Don't truncate essential information at accessibility text sizes or communicate selection through color alone.
- Don't invent place imagery, event destinations, GPS positions or precise network routes.
