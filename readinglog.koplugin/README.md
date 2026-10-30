# Reading Log

**Reading dashboard cards for KOReader's home screens, Simple UI and Bookshelf, made for colour e-ink.**

Activity rings, monthly and yearly charts, reading trends, a monthly
challenge, finish forecasts, library stats, a random pick from your unread
books, your own highlights, a Control centre, a Device card (battery,
storage, memory), five ornaments with no card (the year's books, a streak
flame, a letter board, today's pages, pages turned), a Lifetime pages card
and more: 43 cards, a
reader panel under the reader's top menu (off until you switch it on), a Mini
dashboard and a tabbed Dashboard (Today, Yearly, Monthly, Trends, Library,
Calendar). One plugin works with both home screens.

Full guide, screenshots and releases: https://github.com/stevenzamora1/reading-log

The ring designs and the idea of a reading dashboard come from
[u/fishnoogz](https://www.reddit.com/user/fishnoogz/)'s Reddit post.

## What you need

- [KOReader](https://koreader.rocks) with
  [Simple UI](https://github.com/doctorhetfield-cmd/simpleui.koplugin) 2.7.5 or
  newer, or [Bookshelf](https://github.com/AndyHazz/bookshelf.koplugin) 6.0 or
  newer.
- KOReader's **Reading statistics** plugin switched on (it is by default).

## Install

Copy this `readinglog.koplugin` folder into KOReader's `plugins` folder
(`.adds/koreader/plugins/` on a Kobo, `/mnt/us/koreader/plugins/` on a
Kindle, `<koreader folder>/plugins/` on Android) and restart KOReader.

- **Simple UI:** Simple UI Settings > Home Screen > Layout Editor, open a page,
  tap Add Module and pick any `Reading Log · …` module.
- **Bookshelf:** open its layout editor, tap + Add and pick the Reading Log
  cards (they have a group of their own). The `bookshelf_modules` folder is
  where Bookshelf finds them.

Long-press a card for its settings. Settings live in
`settings/readinglog.lua`, one file for both home screens.

**Updating:** Tools > Reading Log > Check for updates, the App Store plugin,
or replace this folder and restart.

**From the Bookshelf micro-modules version:** on the first start your
settings are copied across, and Reading Log offers to remove the old copy in
`settings/bookshelf/micromodules` (Bookshelf would keep using it otherwise).

## What's in here

- `main.lua`: adds the cards to Simple UI, and Reading Log to the Tools menu
- `bookshelf_modules/`: one small file per card for Bookshelf
- `readinglog/`: the code that draws every card, for both home screens
- `readinglog/locales/`: the translations (see TRANSLATING.md)
- `updater.lua`: Check for updates

## License

AGPL-3.0 (see LICENSE), the same licence as KOReader.
