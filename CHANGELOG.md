# Changelog

## 1.3.0 — 2026-11

- **New theme: Lifelike.** A sticky note as if photographed on the wall: the adhesive strip
  at the top, the paper lifting off and catching the light below an uneven glue line, faint
  creases, a slightly raised bottom-left corner and a warm shadow that widens where the paper
  comes away. Pick it from the note menu (Note Theme); new notes can get it at random.
- **Text color.** Choose the ink of each note from the note menu (Text Color) or from the
  color picker: Graphite, Black, Pen Blue, Red, Green, Sepia. New notes write in a soft
  dark gray (Graphite) instead of black.
- The pin always sits on the visible corner of the paper, on every theme and at any size.
- The alarm-clock button is no longer clipped on tilted notes; the reminder badge uses the
  same symbol as the buttons instead of an emoji.
- The color dot in the note buttons now has a ring, so it stays visible on any paper.
- **Taped** and **Clipped** themes: same soft paper and edge as the Soft theme. The tape is
  now a glossy clear tape, the paper clip a real aluminium gem clip with all its loops.
- Fixed the color picker sometimes showing blank white squares (and an empty
  "Custom color…" button) when the Mac is in Dark Mode.

## 1.2.0 — 2026-11

- **English interface.** Pizzinu now speaks English and Italian and follows the language
  of your Mac: menus, settings, the archive, alerts, reminders, themes and colors.
  Any language other than Italian gets English. Dates and weekdays follow your Mac too.
- **Softer paper edge on the Soft theme.** The dark outline is gone: a barely visible edge in
  the color of the paper, and the shadow does the rest, as on a real sticky note.

## 1.1.1 — 2026-11

- Fixed a crash on Markdown sheets: when a task or a link was scrolled out of view,
  Pizzinu could quit while the pointer moved over the note.
- The × on a note now moves it to the Trash (restore it from the archive, ⌘3); an empty
  note is simply discarded. Notes that earlier versions had only hidden with the × are
  moved to the Trash once, on first launch.
- "Show all notes" brings the notes already on the desktop to the front and no longer
  brings back closed notes. A note restored from the Trash goes back on the desktop.
- Checklists: long items wrap inside the note; with many items the list spreads into
  columns across the note so the text stays as large as possible (12 to 24 pt, like
  Markdown sheets); the list starts at the top and uses the whole note;
  it stays above the bottom controls and scrolls only when nothing else fits, keeping
  the item you are typing in view. Markdown sheets no longer slide
  under the bottom controls either. Turning Markdown off on a task list gives the
  checklist back, with its ticks and levels.
- An empty note says "Double-click to write" under the placeholder.
- Launch at login repairs itself after an update or a move, and Settings explains when
  macOS is waiting for approval or Pizzinu is not in the Applications folder.

## 1.1.0 — 2026-11

- Automatic updates: once a day Pizzinu checks GitHub for a new version and shows
  what's new; "Update and restart" downloads it, checks its Ed25519 signature,
  replaces the app and reopens it. Can be turned off in Settings ▸ Updates.
- "Check for updates…" in the app menu and in the menu bar icon menu.

## 1.0.0 — 2026-11

First public release.

- Floating sticky notes with 14 vector paper themes, including system Liquid Glass (macOS 26).
- Global shortcut ⌥⌘N for a quick note from any app; Esc to go back to work.
- Pin to keep a note above other windows.
- Reminders with a modern time picker: the note shakes when it is due.
- Drag text from any app onto the desktop to create a note.
- Markdown sheets with a floating toolbar, clickable tasks and links.
- Checklists up to three levels.
- Secret notes: password-encrypted (AES-256-GCM, PBKDF2 1M iterations + HKDF), auto-lock,
  hidden from screenshots, 3D folding animation and wax seal.
- Archive as board or list, search, trash; Markdown import/export (one `.md` per note).
- Free fonts only (SIL Open Font License).
