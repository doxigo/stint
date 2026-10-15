---
version: 1
slug: "docs-index-html"
primary_target: "docs/index.html"
related_targets: ["docs/help/index.html","docs/privacy/index.html","docs/terms/index.html"]
---

# Stint public site (docs/)

Scope: landing (docs/index.html) in Persuade mode; help, privacy and terms (docs/*/index.html) in Read mode, same system.
Audience: Teamwork.com users on a Mac who track time daily; Teamwork app-directory reviewers second.
Action: download Stint.dmg; reviewers find help, privacy and terms in one click.
Proof: an interactive popover replica with sample data, real app screenshots (sample data), the public source.
Constraints: static, self-hosted Work Sans, no third-party requests, small first-party script only, light and dark, 390 px without sideways scroll. Teamwork's name as text only. Pink only as dots. Keep every fact and the "independent project, not made or endorsed by Teamwork.com" line.
Answers (2026-10-16): audience as inferred; dark hero stage in both schemes, everything below follows the system; yes to a small live demo script with a no-JS fallback.

## Direction contract

THESIS: The page opens on the product itself: a Mac menu bar at night with Stint's timer already ticking and its popover hanging open, and you can start and pause timers in it. Refuses the category default of headline over one static screenshot on a gradient.

OWN-WORLD: Deep slate night (#1D1C39 to #0E0D20) lit by slow purple and indigo glows; Work Sans set huge and tight (-0.04em) for display, quiet at body size; hairline lavender borders, 18-28 px radii, white primary button on dark, #6438E0 fill on light; pink only as the live dot and full stops. Below the stage the page follows the system: cool white or deep slate, bento panels holding real UI.

STORY: See the timer tick, click Pause and Start, understand "Teamwork's own timers in my menu bar", trust it (Keychain, no servers, public code), download.

FIRST VIEWPORT: Slate header band (brand left; Help, Privacy, Terms, GitHub, white Download pill right). Headline at up to 6rem across two to three lines, left. Lede left, Download button and requirements right at the lede's baseline. The stage starts inside the fold: a 28 px-radius glow panel with a menu bar strip, the purple-and-slate time badge ticking, and the popover dropping beneath it, the main window screenshot behind on the left.

FORM: Brief-pinned (whid.eu's dark launch page for a Mac app: oversized tight display, glowing demo stage, bento of live UI, columned footer), translated into Stint's palette and product. Pinned beats the roll; roll seed key 87656eb6 (assigned index 7) recorded, not built.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
