---
name: Stint (public site)
description: The menu bar at night. Stint's website, a live product stage on night slate, then a calm system-following page.
colors:
  slate: "#1d1c39"
  night: "#0f0e23"
  night-hero-top: "#16153a"
  header-night: "rgba(19, 18, 46, 0.96)"
  purple: "#6438e0"
  purple-press: "#5329cf"
  lilac: "#a48bf7"
  pink: "#ff22b1"
  on-night: "#f4f3fb"
  on-night-muted: "#b9b6d3"
  night-line: "rgba(220, 214, 255, 0.12)"
  bg: "#ffffff"
  bg-alt: "#f6f5fb"
  surface: "#ffffff"
  text: "#1d1c39"
  muted: "#595771"
  line: "#e6e4f0"
  accent-soft: "#f0ecfd"
  code: "#f2f0f9"
  light-button-hover: "#f1edff"
  dark-bg: "#0f0e23"
  dark-bg-alt: "#141329"
  dark-surface: "#18172f"
  dark-text: "#efeef8"
  dark-muted: "#aba8c5"
  dark-line: "rgba(220, 214, 255, 0.11)"
  dark-accent-soft: "rgba(164, 139, 247, 0.13)"
  dark-code: "#211f3f"
  pop-light-bg: "#ffffff"
  pop-light-text: "#1d1d1f"
  pop-light-sub: "#626268"
  pop-light-line: "#e5e5ea"
  pop-light-btn: "#ececf0"
  pop-light-run: "#f2effc"
  pop-dark-bg: "#232325"
  pop-dark-text: "#f2f2f4"
  pop-dark-sub: "#98989f"
  pop-dark-line: "#38383c"
  pop-dark-btn: "#3a3a3e"
  pop-dark-run: "#2d2c3e"
typography:
  display:
    fontFamily: "Work Sans, system-ui, -apple-system, sans-serif"
    fontSize: "clamp(2.75rem, 7.6vw, 6rem)"
    fontWeight: 720
    lineHeight: 0.98
    letterSpacing: "-0.04em"
  page-title:
    fontFamily: "Work Sans, system-ui, -apple-system, sans-serif"
    fontSize: "clamp(2.5rem, 6vw, 4.5rem)"
    fontWeight: 720
    lineHeight: 1
    letterSpacing: "-0.04em"
  headline:
    fontFamily: "Work Sans, system-ui, -apple-system, sans-serif"
    fontSize: "clamp(2rem, 4.6vw, 3.4rem)"
    fontWeight: 700
    lineHeight: 1.02
    letterSpacing: "-0.035em"
  title:
    fontFamily: "Work Sans, system-ui, -apple-system, sans-serif"
    fontSize: "clamp(1.6rem, 3vw, 2.1rem)"
    fontWeight: 700
    lineHeight: 1.12
    letterSpacing: "-0.03em"
  panel-title:
    fontFamily: "Work Sans, system-ui, -apple-system, sans-serif"
    fontSize: "1.3rem"
    fontWeight: 650
    lineHeight: 1.12
    letterSpacing: "-0.02em"
  subhead:
    fontFamily: "Work Sans, system-ui, -apple-system, sans-serif"
    fontSize: "1.125rem"
    fontWeight: 600
    lineHeight: 1.12
    letterSpacing: "-0.01em"
  lede:
    fontFamily: "Work Sans, system-ui, -apple-system, sans-serif"
    fontSize: "clamp(1.125rem, 1.6vw, 1.3rem)"
    fontWeight: 400
    lineHeight: 1.55
  body:
    fontFamily: "Work Sans, system-ui, -apple-system, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "Work Sans, system-ui, -apple-system, sans-serif"
    fontSize: "0.75rem"
    fontWeight: 600
    letterSpacing: "0.08em"
  replica:
    fontFamily: "system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.35
  mono:
    fontFamily: "ui-monospace, SF Mono, Menlo, monospace"
    fontSize: "0.86em"
rounded:
  code: "6px"
  replica-button: "7px"
  pill-sm: "10px"
  button: "12px"
  card: "14px"
  panel: "22px"
  stage: "28px"
  full: "99px"
spacing:
  gutter: "16px"
  wrap: "72rem"
  header: "64px"
  bento-gap: "16px"
  panel-pad: "clamp(22px, 3vw, 32px)"
  section: "clamp(72px, 10vw, 128px)"
  section-head-gap: "clamp(36px, 5vw, 56px)"
  hairline-row: "11px"
components:
  button-light:
    backgroundColor: "#ffffff"
    textColor: "{colors.slate}"
    rounded: "{rounded.button}"
    padding: "0 22px"
    height: "48px"
  button-light-hover:
    backgroundColor: "{colors.light-button-hover}"
  button-big:
    rounded: "{rounded.card}"
    padding: "0 28px"
    height: "56px"
  button-primary:
    backgroundColor: "{colors.purple}"
    textColor: "#ffffff"
    rounded: "{rounded.button}"
    padding: "0 22px"
    height: "48px"
  button-primary-hover:
    backgroundColor: "{colors.purple-press}"
  button-quiet:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    rounded: "{rounded.button}"
    padding: "0 22px"
    height: "48px"
  download-pill:
    backgroundColor: "#ffffff"
    textColor: "{colors.slate}"
    rounded: "{rounded.pill-sm}"
    padding: "0 14px"
    height: "36px"
  site-header:
    backgroundColor: "{colors.header-night}"
    textColor: "{colors.on-night}"
    height: "{spacing.header}"
  panel:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    rounded: "{rounded.panel}"
    padding: "{spacing.panel-pad}"
  panel-featured:
    backgroundColor: "{colors.slate}"
    textColor: "{colors.on-night}"
    rounded: "{rounded.panel}"
    padding: "{spacing.panel-pad}"
  menubar-badge:
    backgroundColor: "{colors.slate}"
    textColor: "#ffffff"
    rounded: "5px"
    height: "22px"
  popover:
    backgroundColor: "{colors.pop-light-bg}"
    textColor: "{colors.pop-light-text}"
    typography: "{typography.replica}"
    rounded: "{rounded.card}"
  popover-row-button:
    backgroundColor: "{colors.pop-light-btn}"
    textColor: "{colors.pop-light-text}"
    rounded: "{rounded.replica-button}"
    padding: "0 10px"
    height: "26px"
  note:
    backgroundColor: "{colors.accent-soft}"
    textColor: "{colors.text}"
    rounded: "{rounded.card}"
    padding: "14px 18px"
  code-inline:
    backgroundColor: "{colors.code}"
    typography: "{typography.mono}"
    rounded: "{rounded.code}"
    padding: "0.12em 0.4em"
---

# Design System: Stint (public site)

Scope: the static site in `docs/` (landing, help, privacy, terms), all sharing `docs/assets/site.css`. This is not the native app's design (that lives in the root `DESIGN.md`, an engineering document), though the palette is the app's own (`Sources/TeamworkTimer/Brand.swift`).

## Overview

**Creative North Star: "The Menu Bar at Night"**

The site opens on the product. Every page starts in a night band: deep slate lit by slow purple and indigo glows, a sticky header with the brand on the left and a white Download pill on the right. On the landing page that night becomes a stage: a slice of a Mac desktop with a menu bar strip, Stint's purple-and-slate time badge ticking, and a working popover replica hanging beneath it, the main window screenshot behind. Work Sans is set huge and tight for display, then quiet at reading size.

Below the night, the page follows the visitor's system setting: cool white or deep slate. Content sits in bento panels that hold real UI (popover strips, menu bar style swatches, duration tables, screenshots) and in hairline lists, never in icon tiles. Docs pages swap the stage for a shorter night page head, then a sticky table of contents beside a 70ch prose column.

Density is relaxed on the landing page (sections of 72 to 128px) and calm for reading on docs pages. Depth is soft and ambient; corners are generous; colour is mostly slate, white and one purple, with pink kept to tiny points of life.

**Key Characteristics:**
- Night slate header and hero or page head in both colour schemes; everything below follows `prefers-color-scheme`.
- Oversized, tight display type (-0.04em) in self-hosted Work Sans.
- A live, clickable product replica instead of a static hero screenshot.
- Bento panels and hairline lists carry real UI and real text.
- Purple as the single accent; pink only as dots and full stops.
- No third-party requests: fonts, script and images are first-party.

## Colors

One brand purple on slate, cool lavender-tinted neutrals, and a pink spark used at dot size.

### Primary
- **Stint Purple** (`purple`): fills in both schemes: the primary button, the running segment of the menu bar badge, the selected day in the popover week strip, the toast. White on it is 6.9:1. Pressed or hovered, it deepens to **Purple Press** (`purple-press`).
- **Night Lilac** (`lilac`): purple as text and line on night grounds, and the page accent in dark mode (purple falls under 4.5:1 there): current-page underline in the header, featured-panel check marks, the sync wire, demo-hint rule.

### Secondary
- **Live Pink** (`pink`): the running dot beside a ticking timer, the dot on the sync wire, the demo hint's dot, and the pink full stop that ends headlines (`.`). Nothing larger.

### Neutral
- **Slate** (`slate`): body text in light mode, the popover header and arrow, the badge's time segment, featured panels, the sync diagram, menu bar style swatches.
- **Night** (`night`) and **Hero Top** (`night-hero-top`): the hero and page-head gradient (top to 62%), and the dark-mode page ground.
- **Header Night** (`header-night`): the translucent sticky header with a 16px blur.
- **On Night** / **On Night Muted** (`on-night`, `on-night-muted`): headings and secondary text on night grounds; headings on night go pure white.
- **Night Hairline** (`night-line`): every border on night surfaces.
- Light page roles: `bg`, `bg-alt` (alternate sections, footer, table heads), `surface` (panels), `text`, `muted`, `line`, `accent-soft` (notes, step numbers), `code`.
- Dark page roles: `dark-bg`, `dark-bg-alt`, `dark-surface`, `dark-text`, `dark-muted`, `dark-line`, `dark-accent-soft`, `dark-code`; the accent becomes Night Lilac.
- **Popover replica palettes** (`pop-light-*`, `pop-dark-*`): macOS system greys, not the site's tinted neutrals, so the replica reads as the real popover. On the hero stage the popover is always dark; set into a light panel (`.pop.mini`) it follows the visitor's scheme, as the real one follows macOS. Selection text is purple in light, lilac in dark.

### Named Rules
**The Pink Point Rule.** Pink is a dot: the live-timer dot, a wire node, a hint marker, a headline's full stop. Never a button, a fill, a border or a word.

**The Night Stays Night Rule.** The header, the landing stage and the docs page head are night slate in both schemes. Only content below them follows the system.

**The Accent Swap Rule.** On light grounds the accent is Stint Purple; on dark grounds it is Night Lilac. Fills stay purple in both.

## Typography

**Display Font:** Work Sans, self-hosted variable woff2 (100 to 900), `font-display: swap` (with system-ui, -apple-system, sans-serif)
**Body Font:** Work Sans (same stack)
**Replica Font:** system-ui stack, used only inside the menu bar, badge, popover replica and toast so they look like macOS.
**Mono:** ui-monospace, SF Mono, Menlo.

**Character:** a geometric grotesque pushed to extremes: very heavy (720) and very tight at display size, ordinary and open at 17px body.

### Hierarchy
- **Display** (720, `clamp(2.75rem, 7.6vw, 6rem)`, 0.98): the landing headline only, max 11em, white on night.
- **Page title** (720, `clamp(2.5rem, 6vw, 4.5rem)`, 1): docs page heads.
- **Headline** (700, `clamp(2rem, 4.6vw, 3.4rem)`, 1.02, -0.035em): landing section heads and the trust statement.
- **Title** (700, `clamp(1.6rem, 3vw, 2.1rem)`, -0.03em): prose h2 and Get panel headings.
- **Panel title** (650, 1.3rem) and **Subhead** (600, 1.125rem): bento panel and feature-list h3.
- **Lede** (400, `clamp(1.125rem, 1.6vw, 1.3rem)`, 1.55): under the display, max 33em, muted on night with white `strong`.
- **Body** (400, 1.0625rem, 1.6): prose max 70ch; `text-wrap: pretty` on paragraphs, `balance` on headings.
- **Label** (600, 0.75 to 0.8125rem, 0.06 to 0.08em, uppercase): TOC and footer column headings and the Requirements label in a Get panel. Navigation and list labels only.

### Named Rules
**The Tight Top Rule.** Tracking tightens as size grows: -0.04em display, -0.035em headline, -0.03em title, -0.02em to -0.01em at subhead. Body is untracked.

**The Tabular Time Rule.** Every duration or clock uses tabular numerals.

## Layout

A single centred column, `min(72rem, 100% - 32px)`. Landing sections pad `clamp(72px, 10vw, 128px)` vertically and alternate between `bg` and `bg-alt`. Section heads max 40rem, left aligned.

- **Hero row:** headline and lede left; download button and requirements right-aligned at the lede's baseline from 860px; stacked below.
- **Stage:** a three-column grid (flexible, popover 464px, tail 170px) under a 32px menu bar row. Below 860px the popover narrows to 372px and the hint moves under it; below 600px the window screenshot and menu bar tail disappear and the popover fills the stage.
- **Bento:** 12 columns from 860px with 7/5 spans and a tall panel; 16px gaps; one column below.
- **Hairline feature list:** 1, 2 (from 700px), then 4 columns (from 1000px).
- **Trust:** 6fr text, 5fr diagram from 900px.
- **Docs:** 220px sticky TOC beside prose from 960px; below, the TOC becomes a boxed two-column list above the prose.
- **Footer:** brand plus three link columns (2fr 1fr 1fr 1fr) from 860px; two columns below; a legal row under a hairline.
- **Header:** 64px; below 600px the nav wraps to its own full-width row and the header height token becomes 96px for scroll padding.
- Works at 390px without sideways scroll.

## Elevation & Depth

Depth comes from light, not stacking: glow gradients on night grounds, and one soft ambient lift on panels and figures. Night surfaces are bordered by lavender hairlines rather than shadowed.

### Shadow Vocabulary
- **Lift, light** (`0 1px 2px rgba(29,28,57,0.05), 0 18px 40px -22px rgba(29,28,57,0.28)`): panels, bleed screenshots, prose figures.
- **Lift, dark** (`0 1px 2px rgba(0,0,0,0.3), 0 22px 44px -24px rgba(0,0,0,0.7)`): the same roles in dark mode.
- **Light button on night** (`0 8px 24px -10px rgba(4,3,16,0.6)`, hover `0 12px 28px -10px rgba(4,3,16,0.7)`).
- **Stage window** (`0 30px 70px -20px rgba(5,3,20,0.75), 0 0 0 1px rgba(255,255,255,0.08)`).
- **Popover** (`0 0 0 0.5px` edge plus `0 30px 80px -10px` deep drop): the replica's macOS-like float.
- **Toast** (`0 8px 20px -10px rgba(29,28,57,0.6)`).

### Named Rules
**The Lit Night Rule.** Night surfaces gain depth from radial purple (`rgba(100,56,224,0.42 to 0.55)`) and indigo glows, never from shadows.

## Shapes

Generous, soft corners that grow with the element: 6px code, 7px replica buttons, 10px pill, 12px buttons and images, 14px cards, notes, tables and the popover, 22px panels and the sync diagram, 28px for the stage top (22px on phones). Fully rounded only for chips, the toast, the updated stamp and circular markers. Borders are 1px hairlines everywhere; the popover arrow is a 14px slate square rotated 45 degrees.

## Components

### Buttons
- **Shape:** gently rounded (12px; 14px at the big size; 10px for the header pill).
- **Light:** white with slate text, the primary call on night grounds (48px, `0 22px`); hover tints to `light-button-hover`, lifts 1px and deepens its shadow.
- **Primary:** Stint Purple fill, white text; hover Purple Press. For calls on light grounds.
- **Quiet:** surface fill, hairline border; hover turns border and text to the accent.
- **Big:** 56px, `0 28px`, 1.0625rem.
- **Download pill:** the Light button at 36px in the header, without shadow.
- **States:** press shifts down 1px and scales to 0.99; transitions use the out-expo ease. Download buttons carry a stroked SVG icon.

### Header
Sticky translucent night band on every page. Brand mark plus "Stint" (650) left; nav links muted on night, white on hover; the current page is white with a 2px lilac underline offset 0.45em. Focus rings turn white on night.

### Hero stage and popover replica (signature)
A 28px-radius glow panel (layered purple, indigo and violet radial gradients over a 160-degree slate gradient) with a blurred translucent menu bar strip. The **menu bar badge** is two segments: a 22px purple glyph square and a slate time readout, 5px radius, system font, tabular; paused, both segments go transparent with a 16% white hover. The **popover** has a slate header with the date and day total, a week strip with the selected day in a purple circle, an uppercase section row, timer rows separated by inset hairlines (running row tinted, with a pink dot before its time), 26px row buttons and a pill-chip footer. It opens with fade plus scale from 0.96. A short hint with a lilac rule and pink dot sits to its right. `demo.js` makes Start and Pause real with sample data; without script the open popover stays static.

### Bento panels
- **Corner:** 22px. **Background:** surface. **Border:** 1px line. **Shadow:** lift. **Padding:** `clamp(22px, 3vw, 32px)`.
- Muted body text max 34em; art sits at the bottom (`margin-top: auto`); screenshots bleed off the right and bottom edges with a 12px top-left corner.
- Contents are real UI: a mini popover, menu bar style swatches (slate tiles), a duration table, pinned tasks with key caps, a toast.

### Hairline lists
Durations, pinned items and the four-up feature list: rows separated by 1px `line` borders, 11px row padding (24px in the feature list), no cards. Values in the accent, notes in muted.

### Check lists and steps
Checks are a CSS-drawn accent tick (lilac in featured panels). Steps use 34px circular counters in `accent-soft` with accent numerals.

### Trust diagram
A slate panel lit by a central purple glow: nodes (14px radius, 6% white fill, night hairline, 40px icon square) joined by a 2px lilac gradient wire with a pink dot at its middle. Teamwork appears as a generic icon plus its name in text.

### Get panels
Two equal panels from 860px. The featured one is slate with a corner purple glow, muted lists, white links and a Light big button; the other is a regular panel with numbered steps and a Quiet button.

### Docs page head, TOC and prose
Page head: night gradient with two glows, page title, muted intro max 40em. TOC: uppercase label, list on a 1px left rail, links muted with a 2px accent left marker on hover. Prose: 70ch, accent list markers, sections divided by hairlines, figures with 12px radius and lift, an "updated" pill stamp.

### Tables, code and notes
Tables sit in a 14px bordered scroll box, `bg-alt` header row, hairline row dividers. Inline code on the `code` tint at 6px; pre blocks at 12px with a hairline; key caps with a hairline and inset bottom edge. Notes are `accent-soft` with a 22% accent border at 14px.

### Footer
`bg-alt` with a top hairline, muted 0.9375rem text, uppercase column labels in text colour, links muted turning to text with underline on hover; legal row under a hairline carrying the independence line.

### Motion
- **Glow drift:** the hero glow layer drifts and scales by 6% over 22s, alternating.
- **Hero rise:** headline, lede and stage fade up 14px from a 6px blur over 0.9s (stage 1.1s), staggered 0.08s and 0.18s; only when script is present.
- **Popover open:** opacity 0.18s and transform 0.28s from `scale(0.96) translateY(-4px)`; closing is 0.14s.
- Easing: `cubic-bezier(0.16, 1, 0.3, 1)`. Every animation and smooth scrolling sits behind `prefers-reduced-motion: no-preference`.

## Do's and Don'ts

### Do:
- **Do** open every page on night slate (header plus hero stage or page head) in both schemes, and let everything below follow the system.
- **Do** use Stint Purple for fills and Night Lilac for accent text and lines on dark grounds.
- **Do** end display and headline statements with a pink full stop when they are sentences (`<span class="dot">.</span>`).
- **Do** fill panels with real product UI or screenshots of sample data.
- **Do** keep Work Sans self-hosted and every asset, script and font first-party.
- **Do** put every animation behind `prefers-reduced-motion: no-preference`.
- **Do** use tabular numerals for all times and durations.

### Don't:
- **Don't** use pink for buttons, fills, borders or text larger than a full stop.
- **Don't** show Teamwork's logo or brand marks; write its name as text, and keep the "independent project, not made or endorsed by Teamwork.com" line.
- **Don't** load anything from a third party: no font CDNs, analytics or embeds.
- **Don't** use purple `#6438e0` as text on dark grounds; it fails 4.5:1 there.
- **Don't** build icon tiles or feature cards with a glyph and a sentence; use real UI or hairline lists.
- **Don't** use the system font outside the macOS replica elements.
