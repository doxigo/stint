# Product

<!-- impeccable:product-schema 1 -->

## Platform

web (the public site in `docs/`). The product itself is a native macOS app; see DESIGN.md for the app.

## Users

People who log their working time in Teamwork.com and work on a Mac, every day: start a timer when they pick up a task, pause for lunch, log the day before they leave. Second audience: Teamwork's app-directory reviewers, who check the public pages (landing, help, privacy, terms) for facts and trust.

## Product Purpose

Stint keeps Teamwork.com time tracking in the macOS menu bar, so starting, pausing and logging time takes a click or a keystroke instead of a browser tab. It replaces Teamwork's own Electron desktop timer. Success: a visitor understands in seconds that Stint is a fast native timer that writes straight to Teamwork, downloads it, and signs in.

## Positioning

Stint uses Teamwork's own server timers: a timer started on the web shows up in Stint and the other way round, with no separate service or sync layer in between. It is native SwiftUI for Apple silicon, not a web wrapper.

## Operating Context

- Lives in the menu bar: live time in the status item, a popover for today (timers, logged time, week strip, daily target), and a main window (Timers, Today, This Week, Pinned, Starred Projects, My Tasks, Settings).
- Sign-in: Sign in with Teamwork, or under Advanced an API token or your own Developer Portal app. Credentials in the macOS Keychain.
- Distributed as `Stint.dmg` from GitHub Releases; current builds are unsigned, so macOS asks for approval on first open.

## Capabilities and Constraints

- Requires macOS 26 or later, Apple silicon, a Teamwork.com account. Free.
- Talks only to the user's Teamwork site and teamwork.com (sign-in). No analytics, no tracking, no servers of its own.
- The site is fully static, self-hosts its fonts and makes no third-party requests (the privacy page promises this). Light and dark mode, phone widths without sideways scrolling, fast loading.
- No license is granted yet: the code is public but terms say so.

## Brand Commitments

- Name: Stint (formerly Teamwork Timer); "Stint for Teamwork" in full.
- Palette from `Sources/TeamworkTimer/Brand.swift`: slate #1D1C39, purple #6438E0 (lighter #9C82F5 for text on dark), pink #FF22B1 only as small dots and accents, never on buttons or large text.
- Teamwork's brand rules (brand.teamwork.com): Teamwork's name only as text, never its logo or symbol, nothing that imitates it.
- Always say: an independent project, not made or endorsed by Teamwork.com.
- Voice: plain, short, second person, concrete (keystrokes and clicks, not adjectives).

## Evidence on Hand

- App screenshots with sample data: `docs/screenshots/` (hero, popover light/dark, today, week dark, settings, menu bar badge).
- App icon (ring) and a 1024 px logo: `docs/assets/icon.png`, `docs/brand/stint-logo-1024.png`.
- No testimonials, user counts, reviews or benchmarks exist. Never invent them.

## Product Principles

1. Time tracking should take a second, then get out of the way.
2. Teamwork stays the source of truth; Stint is a fast client over it.
3. Your data goes to Teamwork and nowhere else, and the public code lets anyone check.
4. Native means native: system conventions, keyboard first, light and dark.

## Accessibility & Inclusion

WCAG 2.2 AA on the site: contrast, keyboard focus, reduced motion respected, meaningful alt text on every screenshot.
