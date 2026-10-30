# Changelog

## 1.4.0

- **One plugin for Simple UI and Bookshelf.** Reading Log is now a KOReader
  plugin, `readinglog.koplugin`, that works with either home screen: Simple
  UI as before, and Bookshelf 6.0 or newer, which loads the cards from the
  plugin's `bookshelf_modules` folder. It installs and updates like any
  other plugin (copy the folder into `plugins`, the App Store plugin, or
  Tools > Reading Log > Check for updates), with no files to copy into
  Bookshelf's settings. Both home screens share one settings file,
  `settings/readinglog.lua`. The micromodules zip is gone.
- **Moving from the Bookshelf micro-modules version:** your settings are
  copied across on the first start, and your Bookshelf layouts keep their
  cards (they have the same names). Reading Log then offers to remove the
  old copy in `settings/bookshelf/micromodules`, which Bookshelf would
  otherwise keep using, and asks you to restart.
- **Bookshelf's card colours:** a card you give colours of its own with
  Bookshelf's palette icon now shows them, even with Look and colours set to
  "Framed, in the theme" (issue #4).
- **Bookshelf's book calls:** opening a book and showing its book menu use
  Bookshelf's own `ctx.open_book` and `ctx.show_book` (Bookshelf 6.0.2 and
  newer), and taps in the full-screen view go by where Bookshelf says the
  card is. Older Bookshelf versions work as before (issue #5).
- With Bookshelf, times now follow KOReader's 12- or 24-hour clock like
  every other card and Bookshelf's own clock, and French is available too.
- **Quote of the day: Another is random now.** It used to step to the next
  highlight of the same book, so it read through a book in order. Now it
  picks any highlight at random, never the one just shown, and never more
  than two in a row from one book while you have others. Quote of the day 2,
  3 and 4 keep the same two-in-a-row rule. With Bookshelf, the day still
  starts on the same quote as Bookshelf's own card.
- Brazilian Portuguese: "this week against last" sentences read correctly
  ("nem na semana passada").
- **Device**, a new card: the battery large, then storage free, the memory
  KOReader is using, Wi-Fi and the front light, each with a level bar (red
  when storage or memory is nearly full, or the battery low). It reads them
  once a minute while it's on screen and redraws only when something
  changed. Four looks: Plain, Hearts (Cute: a heart that empties as the
  battery runs down, and pastel pills), System monitor (Cyber: a segmented
  ring and a readout) and Candle (Dark Academia: a candle burning down
  beside a ledger). Tap it for KOReader's battery statistics. A reader with
  a style already on gets its Device look too.
- **Lifetime pages**, a new card: every page you've ever turned in
  KOReader, how many a day on average, a bar to the next round number, and
  this year's, this month's and this week's pages. Four looks: Plain, Hearts
  (Cute), Data counter (Cyber) and Ledger (Dark Academia). It can go on any
  Dashboard page.
- **Ornaments**, five new modules with no card: they hang straight on the
  wallpaper, or stand on Bookshelf's shelf among your books, each with a
  look for every style. **Books this year** (books in dark cloth with the
  count standing on top in ivory figures, a heart sticker, a glitch billboard or a
  brass plaque, with a title of your own if you want one), **Streak flame**
  (a flame that grows with your streak, a heart with a flame, a neon flame
  or a candle that stands taller), **Letter board** (your own words on a
  felt letter board, a light box, an LED marquee or a chalkboard, stars on or
  off), **Today's pages** (a till receipt, a sticky note, a heart monitor
  or a library card with the last few days) and **Pages turned** (every
  page you've read, or this year's: a flip counter, a pink banner, a data
  counter or an open book). A reader with a style already
  on gets their looks too.
- **Reader panel** (off until switched on in Tools > Reading Log): the
  reader's top menu opens on a small panel: the cover, title and author,
  two lines of figures (the page, percent, time left and this book's time
  and days; then today's pages, time and streak in the colours of today's
  rings beside them), a thin progress bar (this week's rings if you want
  them), and a row of buttons in your style. Three buttons as it
  comes (Wi-Fi, bookmarks, light), up to eight, each with any action from
  KOReader's gesture list and an icon of your choice: a glyph, one of
  KOReader's icons, or a PNG, JPEG or SVG of your own. Every part can be
  switched off. Tap the open tab to come back to it. Quick to open: the
  numbers come from a small read of today's statistics and what's in
  memory.
- **Today's figures on the home screen count the reading you've just done.**
  Bookshelf 6 keeps a book open behind the shelf for a while after you go
  home, and KOReader only saves that sitting's pages when the book really
  closes, so the cards showed the figures from before it until KOReader
  restarted. They now take in what the open book hasn't saved yet. The
  ornaments on Bookshelf's top panel also look once a minute and redraw when
  a figure they show changes.
- **Continue reading starts with the book you're reading**, the same one
  as Bookshelf's top card: the book open in the reader, or opened last,
  even one you've only just started (it used to wait for the book to pass
  0% and be saved, so the book before it showed first). Its progress is
  the one the reader has now. A book marked finished or on hold, or read
  to the end, still moves on to the next.
- **Library stats count books the way Bookshelf does.** With Bookshelf,
  each book counts under the status Bookshelf gives it, so the figures match
  its own Shelf size card. A book marked New (or, with older Bookshelf
  versions, one with no status) used to count as Reading if it had a
  percentage left in it, so Reading came out higher than Bookshelf's count.
  Continue reading follows the same rule.
- **Simple UI: no white box round framed cards.** A card on its own that
  draws its own frame (Cyber, Dark Academia, or Cards on their own set to
  framed) and the ornaments no longer sit inside Simple UI's module box, so
  there's no margin of Simple UI's colour round them over a wallpaper. The
  other cards sit in Simple UI's box as before.
- **Copying from a Mac:** the hidden `._` files a Mac leaves beside every
  file it copies onto the e-reader are removed from the plugin's folder when
  KOReader starts, so Bookshelf no longer logs "micro-module failed to load"
  for each of them.
- **Style: Cyber**, a third style beside Default and Cute: a black page in
  neon yellow and cyan, cards with two corners cut off, and every card's
  cyber look at once. Rings become rings of segments that light up (a
  missed day in red), Continue reading a HUD with the cover in corner
  brackets and a segmented progress bar, the Book club a data stream, the
  Year goal a terminal syncing your latest finished books over a segmented
  bar (SYNC COMPLETE at your goal, or shards if you'd rather), the Monthly
  challenge a neural network the signal moves through link by link as you
  read (a step
  every 1.3% or so, the output node firing in magenta at 100%), the quote
  cards a terminal window, the cover calendars covers in
  brackets with the time read on a tag coloured by how long you read,
  Reading trends a diagnostics readout with warning stripes on Worth a look,
  the charts neon bars and straight lines, Today's timeline a skyline, and
  the Finish forecast a countdown ("T-8"). The clock and page titles get a
  glitch, and the tabs and buttons go square. Default puts your theme and
  accents back. Each look can also be picked on its own, in any theme, light
  or dark. The Cyber drawings live in a file of their own that is only read
  when something uses them.
- **Cyber** theme and two neon accents (yellow and cyan) in Look and colours.
- **Style: Dark Academia**: parchment cards on a dark study's page, set in
  a serif, square corners with a thin brass rule inside, and every card's
  dark academia look at once. Rings become pocket watches (a hand each for
  pages, minutes and streak, the covered part of the face washed in its
  colour, the hand back at XII at the goal), Continue
  reading hangs its cover in a gilt frame with a brass plate and writes your
  progress with a fountain pen, the Book club keeps a tally and stamps
  finished picks, the Year goal is an ink sketch of a globe whose triangles
  are shaded in as you read (and gets a brass equator when you reach it),
  the Monthly challenge is a chess board (the Immortal Game, Anderssen
  against Kieseritzky, 1851, plays out from the starting position as you
  read, one move every 2% or so, with a king in check marked, and ends in
  White's checkmate at 100%, the black king knocked over on an oxblood
  square), the quote cards are manuscript pages
  with a big initial and a wax seal, the cover calendars hang in gilt frames,
  Reading trends are library catalogue cards, every bar chart is a row of
  candles (only today, or this month, lit), line charts are engraved with
  hatching under the line and a wax seal on the latest point, Year in covers
  is a gallery wall of gilt frames, Today's timeline is a celestial
  chart from sun to moon, and the Finish forecast is an almanac entry
  ("Tuesday, 3 November"). The tabs are names underlined in brass. Default
  puts your theme and accents back, and each look can also be picked on its
  own. Like Cyber, its drawings are only read when something uses them.
- **Dark Academia** theme and two accents (oxblood and brass).
- Reading trends shows the year's figure as "year: 43".

## 1.3.0

- **Cover calendar:** the month's pages, books and time read along the top,
  then every day with the cover of the book you read most that day and the
  time read under it; a second book fans out behind it. Tap a day for its
  books. It has its own Dashboard tab, **Calendar**.
- **Week in covers:** this week's days with their covers in one row, as a
  card or a small card in the Mini dashboard.
- **Quote of the day 2, 3 and 4:** more quote cards, each with a random
  highlight of its own, never the same one as your other quote cards. Another
  on one doesn't change the others.
- The Cover calendar has a **Today** button, and bigger buttons all round.
- **Hearts instead of rings:** Activity, Week and Month rings and the Mini
  dashboard can show two hearts that fill up, the outer one with pages and
  the inner one with time. A day that misses its goals gets a broken heart.
- **Monthly challenge as a flower:** a peony whose petals colour in as you
  get closer to the month's goal, and sparkles when it's done.
- **Book club garden:** each pick's progress bar grows as a stem with
  leaves and a bud, ending in a flower, and finished covers get a dragonfly
  sticker.
- **Year goal as a jar of hearts:** a heart for each book finished; past the
  goal the lid pops off and the hearts heap over the rim.
- **Style: Default or Cute** in the Dashboard's settings switches every cute
  look on or off at once (hearts, flower, garden, jar, notebook paper,
  polaroids, scrapbook, sticky notes, cozy charts, the sky and the desk
  calendar).
- **Quote cards on notebook paper:** lined paper with a margin line, punched
  holes and washi tape on the corners.
- **Cover calendars as polaroids:** each day's cover in a white frame, a
  little crooked, with the time read written on it.
- **Continue reading as a scrapbook:** the cover as a taped polaroid and the
  progress bar as a vine.
- **Reading trends on sticky notes:** each trend on a pastel note with washi
  tape and a folded corner, a sprout, drooping leaf or sun instead of the
  arrows, and a highlighter swoosh under the figure.
- **Finish forecast as a desk calendar:** the finish date on a tear-off page
  with the day circled in a heart, and date stickers for the other books.
- **Cozy charts:** bars as book spines on a shelf with a heart on the best
  one, and lines with a soft hill, hearts on the points and a flower on the
  latest.
- **Today's timeline as a sky:** sun to moon, clouds for daytime sittings,
  stars for evening ones, and a heart over now.
- **Control centre:** a button can show a PNG or JPEG picture of your own
  instead of an icon: just the picture, with no tile behind it (its name
  turns the accent colour while the button is on).
- Room for eight Dashboard tabs.
- **Faster:** a card that hasn't changed is copied back from memory instead
  of drawn again, so going back to a tab, the clock's minute redraw and a
  closing menu redraw about twice as fast. The Cute drawings (polaroids,
  hearts, flowers, stickers) draw two to four times faster.
- **One step instead of two:** a Dashboard tab (or another month) is drawn
  whole in one go, instead of with gaps that fill in a moment later.
- **Easier on the battery:** turning a Dashboard tab no longer flashes the
  screen; it gets a quick update instead (KOReader still flashes every so
  often, by its own Full refresh rate, to clear ghosting). The minute redraw
  does about half the work, and the books you're reading and the year's
  books are worked out again when you open a book (or every few minutes),
  not every minute.

## 1.2.0

- **Languages:** Reading Log follows KOReader's interface language. Italian
  (thanks to [DevGizmo86](https://github.com/DevGizmo86), who also built the
  translation system), Spanish and Brazilian Portuguese. It uses the language
  KOReader is actually showing, including its automatic system language, and
  notes in KOReader's log which translation it loaded.
- Tab names and the Random pick heading get a little smaller instead of being
  cut off when a translation is longer.

## 1.1.0

- **Reading trends:** your last 90 days against your last year, like the
  Trends in Apple's Fitness app: time read, pages, reading days, session
  length, reading speed and books finished, sorted into Keep it going, Worth
  a look and Needs more data.
- **Monthly challenge:** one goal for the month as a big ring. It picks pages,
  minutes or reading days from your last three months, or you set your own,
  and shows how much each day still needs and whether you're on pace.
- **Finish forecast:** when you'll finish the book you're reading at your
  recent pace, the others you're in the middle of, and how many books your
  year is on pace for.
- **This week vs last:** like Apple Health, "You're averaging more minutes a
  day this week than last week", with a bar for each week. Time read, pages
  or both, and months or years instead of weeks.
- **Control centre:** one to eight buttons with icons for any action (lit up
  when they're on), plus brightness and warmth.
- **Library stats:** how many books you own, have read, are reading and
  haven't started.
- **Most-read authors:** by books finished or by hours read.
- **Random pick:** a book you haven't started, new every day, week or month
  or when you tap Another, from the whole library or one collection, and
  only the genres or authors you choose. In a series it only offers the next
  book.
- **Quote of the day:** one of your own highlights each day.
- **Today's timeline:** each sitting today along the day, and the book it was.
- Two new Dashboard pages: **Trends** (Monthly challenge beside Finish
  forecast, then Reading trends) and **Library** (Library stats, Random pick
  beside Most-read authors, Quote of the day). Any card can go on any page.
- **Pages of your own:** add pages to the Dashboard (up to seven tabs), move
  tabs, and put the whole Dashboard back as it came in one tap.
- **Mini dashboard:** one row of up to three small cards for the top of the
  home screen. As it comes: the book you're reading, with a small row of
  today's rings under its progress (pages, minutes and streak), then the
  Control centre. The library cards
  and Today's timeline can go in it too.

## 1.0.0

First public release.

- 21 cards for Bookshelf's home screen and full-screen view: Banner,
  Continue reading, Activity rings, Week rings, Month rings, Month totals,
  Pages per day, When you read, Longest reads (month), Longest reads (year),
  Time read by month, Books and pages, Year in covers, Year goal, Top genres,
  Book club, TBR shelf, Finish by, This week, Reading heatmap and Recently
  finished.
- A Dashboard that puts them together as three tabbed pages, Today, Yearly
  and Monthly, with every page editable on the device. The Monthly page steps
  back through the last twelve months.
- Cards on their own match Bookshelf's look, including its dark theme.
- Three themes (White, Dark, Paper) and twelve accent colours chosen for
  colour e-ink, with screen updates that clear ghosting.
- Any card can run a plugin, a KOReader action or a menu entry when tapped.
