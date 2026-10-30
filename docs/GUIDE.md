# Reading Log guide

Every card and setting in one place. For the quick version, see the
[README](../README.md).

The ring designs and the idea of a reading dashboard come from
[u/fishnoogz](https://www.reddit.com/user/fishnoogz/)'s Reddit post.

## Install

Reading Log is one KOReader plugin for both home screens: Simple UI (2.7.5
or newer) and Bookshelf (6.0 or newer).

1. Copy the release's `readinglog.koplugin` folder into KOReader's
   `plugins` folder (`.adds/koreader/plugins/` on a Kobo, a hidden folder;
   `/mnt/us/koreader/plugins/` on a Kindle). Or install it with the App
   Store plugin.
2. Restart KOReader.

Settings are kept in `settings/readinglog.lua`, one file for both home
screens, outside the plugin folder, so updates keep them. To update, use
Tools > Reading Log > **Check for updates**, the App Store plugin, or copy the
new folder over the old one.

**From the Bookshelf micro-modules version (1.3 and before):** your settings
are copied across on the first start, and Reading Log offers to remove the
old `alm_*.lua` files and `almanac` folder from
`settings/bookshelf/micromodules/` (Bookshelf would keep using them
otherwise). Restart when it asks. Your Bookshelf layouts keep their cards.

## Set up the Dashboard

**With Bookshelf:**

1. Bookshelf menu > Settings > Micro modules: turn on **Full-screen button**.
2. Tap that button, at the bottom right of the home screen.
3. Long-press a module to open the layout editor, tap **+ Add** and add
   **Reading Log · Dashboard** (the Reading Log cards have their own group).
4. Make the Dashboard the biggest size and remove every other module.

**With Simple UI:**

1. Simple UI Settings > **Extra Custom Screens**: create one.
2. Open its layout and add **Reading Log · Dashboard** on its own.
3. Long-press the Dashboard and set **Top Margin** to 0 and **Height** to
   Fill the page.

## The pages

| Today | Yearly | Monthly |
| --- | --- | --- |
| ![Today](images/today.png) | ![Yearly](images/yearly.png) | ![Monthly](images/monthly.png) |
| Banner, Continue reading, Activity rings beside Week rings, Book club | Time read by month beside Longest reads (year), Books and pages, Year in covers | Month rings beside Month totals, Pages per day, When you read beside Longest reads (month) |

The fourth page, **Trends**, has Monthly challenge beside Finish forecast,
then Reading trends. The fifth, **Library**, has Library stats, Random pick
beside Most-read authors, then Quote of the day. The sixth, **Calendar**, is
the Cover calendar, with arrows at the top to step back through the months.

Tap the tabs at the bottom to switch pages.

**Looking back a month:** on the Monthly page, the left arrow at the top
steps back a month (up to twelve) and the right arrow steps forward. When
you're on another month, a **Today** button appears to bring you back. Every
card on the page follows.

### Default, Cute, Cyber or Dark Academia

**Style** in the Dashboard's settings (and in Look and colours on any card)
switches every cute (or cyber, or dark academia) look at once:

- **Cute:** hearts instead of rings, the Monthly challenge as a flower, the
  Book club as a garden, the Year goal as a jar of hearts, the quote cards on
  notebook paper, the cover calendars as polaroids, Continue reading as a
  scrapbook, Reading trends on sticky notes, the charts as book spines and
  hearts, Today's timeline as a sky, the Finish forecast as a desk
  calendar, the Device card's battery as a heart, Lifetime pages with a
  row of hearts, and the ornaments as a
  heart sticker, a heart with a flame, a light box, a sticky note and a
  pink banner.
- **Cyber:** the Cyber theme (a black page, neon yellow and cyan, cards with
  two corners cut off) and every cyber look: rings of segments, Continue
  reading as a HUD, the Book club as a data stream, the Year goal as a
  terminal syncing your books, the Monthly challenge as a neural network, the quote cards as a terminal, the cover
  calendars in brackets, Reading trends as diagnostics, neon charts, Today's
  timeline as a skyline, the Finish forecast as a countdown, the Device
  card as a system monitor, Lifetime pages as a data counter, and the
  ornaments as a glitch billboard, a neon
  flame, an LED marquee, a heart monitor and a data counter.
- **Dark Academia:** the Dark Academia theme (parchment cards on a dark page,
  a serif, square corners with a thin brass rule) and every dark academia
  look: pocket watches for the rings, Continue reading framed with a fountain pen, a ledger
  for the Book club, a globe for the Year goal, a chess board for the Monthly
  challenge, manuscript quote cards, gilt-framed calendars, catalogue cards
  for Reading trends, candles for the charts, a celestial chart for Today's
  timeline, an almanac for the Finish forecast, a candle and ledger for
  the Device card, a ledger for Lifetime pages, and for the ornaments a brass
  plaque, a candle, a
  chalkboard, a library card and an open book.
- **Default:** all of them back as they came (after Cyber or Dark Academia,
  with the theme and accents you had before).

Each card can still be changed on its own afterwards. When the cards don't
all match one style, none is ticked and the settings say so.

### Notebook paper and polaroids

- **Quote cards, Look: Notebook paper** (one setting for all four quote
  cards): the quote is written on a sheet of lined paper with a pink margin
  line and punched holes, the lines running under the words, and washi tape
  across the top corners.
- **Cover calendars, Look: Polaroids** (one setting for the Cover calendar
  and Week in covers): each day's cover is a polaroid, a little crooked, with
  the time read written on its wide bottom edge. A day with two books has a
  second polaroid behind.

### Scrapbook and sticky notes

- **Continue reading, Look: Scrapbook:** the cover is a polaroid taped to
  the card, a little crooked, and the progress bar grows as a vine with
  leaves and a bud at its tip.
- **Reading trends, Look: Sticky notes:** each trend is on a pastel sticky
  note with a bit of washi tape and a folded corner. A sprout means going
  up, a drooping leaf going down, a little sun not enough data yet, and the
  figure is underlined with a highlighter swoosh.
- **Finish forecast, Look: Desk calendar:** the finish date is on a little
  tear-off calendar page with the day circled in a heart and washi tape on
  the corner, with the weekday and "in 7 days" beside it. The other books
  get a date sticker each.

### Book spines and hearts (the charts)

One setting, **Charts: Book spines and hearts**, in the settings of any card
with a chart (Time read by month, Pages per day, When you read, This week,
This week vs last, Books and pages, and the Monthly challenge's line):

- **Bars** become books standing on a wooden shelf, in pastel colours with two
  thin bands near their ends. Today (or this month) is in the accent colour,
  and the best day, month or hour gets a heart on top. In This week vs last
  the two books lie flat.
- **Lines** get a soft hill underneath, small hearts on their points and a
  flower on the latest one.

### Today's timeline as a sky

**Look: Sky** turns the day's line into a strip of sky, from a little sun in
the morning to a moon at night, with the colours of the day in between (dawn,
blue sky, sunset, night with stars). Each sitting is a cloud during the day
or a star in the evening, bigger the longer you read, and a small heart over
a thin line marks now. The list of sittings shows each one's cloud or star
beside its time. The Mini dashboard's timeline follows the card.

### The Cyber looks

| | |
| --- | --- |
| ![Today in the Cyber style](images/today-cyber.png) | ![Yearly in the Cyber style](images/yearly-cyber.png) |

Each one is also a **Look** in its card's settings, so you can mix them with
the others, in any theme:

- **Rings, Shape: Segments** (one setting for every rings card): each ring is
  a circle of segments that light up clockwise. A day that missed its goals
  is drawn in red.
- **Continue reading, Look: HUD:** the cover in corner brackets, the
  progress as a bar of slanted segments, and square buttons.
- **Book club, Look: Data stream:** slanted segments for the club's books,
  covers in brackets, a segmented bar for each pick, and FINISHED on a block
  of colour.
- **Year goal, Look: Terminal:** a netrunner's terminal syncing your year.
  The books you finished most recently scroll past as files marked OK, and
  under them are a segmented bar, the count ("29/36 BOOKS") and a cursor.
  The status reads ahead, behind (in red) or on track; at your goal it says
  SYNC COMPLETE in green, and past it the bar and count turn magenta with
  "+3". On a small card the file list goes first, so the bar and count
  always fit. (**Shards**, a lit shard for each book of your goal, is the
  other Cyber option.)
- **Monthly challenge, Look: Neural network:** five layers of nodes. As you
  read towards the goal the signal moves through: each node's links light up
  in yellow one by one, then the node itself in cyan, layer after layer, with
  a broken ring round the node it's heading for. That's 75 steps, so it moves
  on every 1.3% or so. At 100% the output node fires in magenta. (**Reticle**,
  the ring as a sight, is the other Cyber option.)
- **Quote cards, Look: Terminal:** the quote decrypted on a netrunner's
  screen: black with scanlines in a neon frame with two corners cut off, a
  header with warning stripes, a glitched title and a signal meter, the
  command and a decrypt bar, the quote in a monospaced font, its source, and
  a cursor. In a light theme the screen stays black, like a monitor. On a
  small card the extras go first, so the whole quote always fits.
- **Cover calendars, Look: Brackets:** each cover in corner brackets and the
  time read on a tag: in the first accent for two hours or more, the second
  accent for half an hour or more, grey under that. A second book is an
  outline behind.
- **Reading trends, Look: Diagnostics:** square readouts with a coloured edge,
  and warning stripes for Worth a look.
- **Charts: Neon:** bars outlined in neon with a dim fill, and lines drawn
  straight from point to point with diamonds on them.
- **Today's timeline, Look: Skyline:** each sitting a lit tower over a dim
  city, as wide as the sitting and taller the longer you read, and a red line
  for now.
- **Finish forecast, Look: Countdown:** "T-8" (days to go) in big type with
  the date under it in red.
- **Device, Look: System monitor:** the battery as a ring of segments with
  the figure and PWR inside (red when low, cyan while charging), and a
  readout beside it: DSK, MEM, NET and LUM with their values in a monospaced
  font over bars of slanted segments, and a signal meter for Wi-Fi.

### The Dark Academia looks

| | |
| --- | --- |
| ![Today in the Dark Academia style](images/today-academia.png) | ![Yearly in the Dark Academia style](images/yearly-academia.png) |

Each one is also a **Look** in its card's settings, so you can mix them with
the others, in any theme:

- **Rings, Shape: Pocket watch** (one setting for every rings card): each set
  of rings is a pocket watch, with a brass case and crown and a cream face.
  Pages, minutes and streak each get a hand (pages the longest), pointing to
  how far you've got, and the part of the face each has covered is washed in
  its colour (more strongly on the small watches of the Week and Month cards).
  At a goal its band goes all the way round and its hand is back at XII.
  **Brass dial**, each ring engraved on a brass dial, is the other Dark
  Academia shape.
- **Continue reading, Look: Framed:** the cover hangs in a gilt frame with a
  cream mat and rosettes at the corners, with a brass plate under it giving
  the title and author. Your progress is a line written in ink with a
  fountain pen resting where you stopped; when you finish, the line ends in
  a flourish and the pen lifts.
- **Book club, Look: Ledger:** a tally of the club's books (struck in fives),
  covers in gilt frames, each pick's progress written in ink, and FINISHED
  stamped like a library card.
- **Year goal, Look: Globe:** an ink sketch of a globe made of small
  triangles, on a brass stand. The triangles are shaded in from the bottom
  up as you finish books; at your goal the whole globe is shaded and gets a
  brass equator.
- **Monthly challenge, Look: Chess board:** the board starts set up as
  usual, and a real game plays out as you read towards the month's goal: the
  Immortal Game, Anderssen against Kieseritzky, London 1851, with you as
  White. Its 45 moves are spread over the challenge, about one every 2%, so
  the board changes often. The last move is lit in brass and a king in check
  sits on a red square. At 100% White mates with 23. Be7, the black king is
  knocked over on an oxblood square, and the card says Checkmate! The board
  only changes when the card redraws anyway, so it costs no extra battery.
  (**Hourglass**, with sand that falls as you read, is the other Dark
  Academia option.)
- **Quote cards, Look: Manuscript:** the quote on a manuscript page inside a
  brass rule, its first letter a big initial, the book in italic at the
  foot, and a wax seal in the corner.
- **Cover calendars, Look: Gilt frames:** each cover in a gilt frame, the
  time read on a small brass plate.
- **Reading trends, Look: Catalogue cards:** each trend on a library
  catalogue card with a red rule and a punched hole.
- **Charts: Candles:** every bar is a candle in a brass holder, taller the
  more you read, with a short wick so the top of the wax is the reading.
  Only today (or this month) is lit. Line charts are inked, with engraved hatching
  under the line, ink blots on the points and a wax seal on the latest one.
- **Year in covers, Look: Gallery wall:** the year's covers hang in gilt
  frames of slightly different sizes on a dark green wall, like a salon.
- **Today's timeline, Look: Celestial:** the day along an engraved line with
  hour ticks, the sun's path dotted over it from a sun to a moon, each
  sitting a bar of ink, and a star for now.
- **Finish forecast, Look: Almanac:** the finish date written out
  ("Tuesday, 3 November") with "in 9 days" under it and a small ornament.
- **Device, Look: Candle:** a lit candle in a brass holder that burns down
  as the battery runs down, the figure in a serif beside it, and a ledger:
  storage, memory, Wi-Fi and the light in italic with dotted leaders to
  their values.

### Year goal as a jar

Long-press the Year goal card > Module settings > **Look: Jar of hearts**.
A heart drops into the jar for each book you finish, and the jar holds your
goal. When you reach it, it sparkles; past it, the lid pops off and the
extra hearts heap up over the rim ("Goal reached, +3"). For a goal over 150
books, each heart stands for a few books.

### Editing the Dashboard

Long-press the Dashboard > Module settings > **Pages and cards**.

- Pick a page at the top, then tap a row to change its **Card**, what goes
  **Beside it**, its **Height**, or to move or remove it.
- **+ Add a row** adds one (up to six a page).
- **Tab name**, **Title on the page** and **Page shown / hidden** change the
  page itself, and **Move tab left / right** changes where its tab sits.
- **+ Add a page** adds a page of your own (up to eight tabs in all). It
  starts with one card; add rows to it like any other page. **Remove this
  page** takes away a page you added.
- **Put this page back as it came** undoes your changes to one of the
  built-in pages.
- To undo everything at once, long-press the Dashboard > Module settings >
  **Put the whole Dashboard back as it came**. Pages you added are removed;
  each card's own settings and the colours are kept.

## Cards on their own

Any card can also go on its own next to the home screen's own modules: in
Bookshelf's full-screen view or top area, or on any Simple UI page. On
their own the cards use the home screen's colours, including its dark theme.
In Bookshelf, a card you give colours with the palette icon in its layout
editor shows those colours.

In Simple UI, a card that draws its own frame (Cyber, Dark Academia, or
Cards on their own set to framed) and the ornaments sit straight on the
page or wallpaper, without Simple UI's module box round them. The other
cards sit in Simple UI's box like its own modules. With a wallpaper and a
card's **Background Opacity** below Solid, the card draws no frame of its
own and Simple UI's see-through box is its background.

| | | | |
| --- | --- | --- | --- |
| ![Cards](images/cards-1.png) | ![More cards](images/cards-2.png) | ![Home screen](images/home-1.png) | ![Home screen](images/home-2.png) |

## Ornaments: Books this year, Streak flame, Letter board, Today's pages, Pages turned

| | |
| --- | --- |
| ![Books this year (Glitch billboard) and the LED marquee letter board on the shelf](images/shelf-ornaments-cyber.png) | ![The streak candle and the felt letter board on the shelf](images/shelf-ornaments-academia.png) |

These five have no card: they hang straight on the wallpaper, or stand among
the books on Bookshelf's shelf (on the plank), like Bookshelf's own
ornaments. Each has a body of its own, so it reads on any wallpaper, and a
look for every style (picked in its settings, or all at once with the
style). With Bookshelf each starts one cell big; resize it like any module.
They're quick to draw.

**When they update:** whenever the home screen draws them: when you come
back to it from a book, turn the shelf's page or open the full-screen view.
Today's figures count the reading you've just done straight away, even
while Bookshelf keeps the book open behind the shelf (it closes it once
you've been idle for half a minute, and only then does KOReader save that
reading). On Bookshelf's top panel they also look once a minute and redraw
only when a figure they show has changed, after midnight for instance.

**Reading Log · Books this year:** the books you finished this year plus any
read outside KOReader, as on the Year goal. Settings: a **Title** ("My
library", or nothing, as it comes) and the **Look**:

- **Book stack** (Default): four books in dark cloth (navy, green, burgundy,
  brown) with gilt bands and "BOOKS · 2026" on the top one, and the count in
  big ivory figures standing on top of the stack.
- **Heart sticker** (Cute): a pink heart with a white edge and sparkles.
- **Glitch billboard** (Cyber): the count huge in white, split cyan and
  magenta with glitch lines through it, on a black screen with scanlines; a
  yellow BOOKS//2026 tag, 本 ("book") glowing behind, a barcode and LV.29.
- **Brass plaque** (Dark Academia): an engraved plaque with four screws,
  "volumes read" and the year in Roman numerals.

**Reading Log · Streak flame:** your reading streak. The flame grows the
longer the streak runs (full size at a month) and goes grey when there's no
streak. **Flame** (Default: the days in the flame's heart, "day streak" on a
tag), **Heart on fire** (Cute), **Neon flame** (Cyber: a sign hung on two
wires, the flame a pink tube with a cyan core and the days in yellow) or **Candle** (Dark
Academia: a candle in a brass holder that stands taller with the streak, and
a brass plaque).

**Reading Log · Letter board:** words of your own, like a felt letter
board. Settings: **Words** (start a new line wherever you want the board to
break; "So many books, so little time" as it comes), **Stars** shown or
hidden, and the **Look**: **Felt letter board** (Default: white letters on
black felt in a pine frame, with stars), **Light box** (Cute: black letters
in a pink light box, with hearts), **LED marquee** (Cyber: amber letters
made of dots in a metal case with bolts) or **Chalkboard**
(Dark Academia). The words get as big as the board allows.

**Reading Log · Today's pages:** the pages you've read today. **Receipt**
(Default: a till receipt with the date, time read, streak and this week, the
pages in big figures and a barcode; it keeps what fits), **Sticky note**
(Cute), **Heart monitor** (Cyber: a pulse line with one beat for each of
the last seven days, taller the more you read, today's in magenta, and
today's pages and time read under it) or
**Library card** (Dark Academia: the last few days written in by hand,
today's stamped).

**Reading Log · Pages turned:** every page you've turned since you started
keeping reading statistics (today's included), or, with **Count** set to
**This year**, this year's. **Flip counter** (Default: a card for each
digit, split where it flips, in a dark case, "PAGES TURNED" on a plate),
**Pink banner** (Cute: the figures and "pages turned!" on a pink banner
with a white sticker edge), **Data counter** (Cyber: the figures
glitched like the Cyber clock, a bar of segments to the next round number,
and since when)
or **Open book** (Dark Academia: the figures written in ink on the right
page, a red ribbon down the middle, since when on the left). The pages from
before the last year or so are counted once and kept, so it costs no more
to draw than the others.

## The reader panel

| | |
| --- | --- |
| ![The reader panel in the Cyber style](images/reader-panel-cyber.png) | ![The reader panel in the Cute style](images/reader-panel-cute.png) |

Off until you switch it on: Tools > Reading Log > **Reader panel** > **Show
it when the reader's menu opens**. From then on the reader's top menu opens
on a small panel under the row of tabs, instead of the first tab's list:

- **The book:** the cover, title and author, and under them two lines of
  figures: "Page 71/607 · 12% · 02:45 left · 50 m in book · 3 days of
  reading", then "1 page today · 2 m read today · 5-day streak" (in the
  colours of the activity rings when they're shown, so each figure matches
  its ring), then a thin progress bar. Tap it for the book's status.
- **Activity rings:** today's three rings, small, beside the line (tap for
  your reading progress). **Week rings** (off as they come): this week's
  rings in a row, with the week's pages and time read beside them (tap for
  the calendar). They follow the rings shape you
  picked (hearts, segments, pocket watches...).
- **Buttons:** a row of keys in your style (rounded for Default, pastel
  pills for Cute, cut corners for Cyber, brass for Dark Academia). Hold a
  button to see what it does.

The arrow, time and battery stay along the bottom, as always. Tap a tab to
see its list; tap the open tab again to come back to the panel. The reading
you've just done counts in the numbers straight away, without waiting for
the statistics to be saved.

In Tools > Reading Log > Reader panel:

- Each part on or off: the book, today's figures (pages, time, streak), this
  book's figures (days, time), activity rings, week rings. All but the week
  rings are on as they come.
- **Buttons:** how many (none to eight; three as they come: Wi-Fi, your
  bookmarks and the light; more buttons come as night mode, the bottom menu,
  contents, book statistics and sleep), and for each one its **Action**, from KOReader's own list
  (the one gestures use, so it has every KOReader action and the ones other
  plugins add), and its **Icon**: one of Reading Log's glyphs, **KOReader's
  icons** (a grid of the icons KOReader ships, plus any in your own icons
  folder, drawn in the button's colour like the glyphs), or **A picture of
  your own** (a PNG, JPEG or SVG file, in its own colours). Picking a
  new action replaces the old one. **Put this button back as it came**
  undoes your changes.

Wi-Fi, night mode, the light and adding a bookmark run with the panel left
open (Wi-Fi and night mode light up while they're on); anything else closes
the menu first. Don't use it together with another plugin that changes
how the reader's menu opens (such as Shortcuts Toolbar): use one or the
other.

## The Mini dashboard

One row of small cards made for the top of the home screen. With Bookshelf,
turn on Bookshelf menu > Settings > Micro modules > **In the top panel**, then
add **Reading Log · Mini dashboard** there from the layout editor; with
Simple UI, add it to a page like any module.

As it comes it shows the book you're reading (tap it to open the book), with
a small row of today's rings under its progress (pages, minutes and streak),
then the Control centre. Tap the rings for your reading progress.
Long-press it > Module settings to pick up to three cards from Reading and
today's rings, Control centre, Continue reading, Activity rings, This week vs
last, Week rings, Monthly challenge, Finish forecast, Year goal, Today's
timeline, Random pick, Quote of the day, Library stats and Week in covers.
It shows as many
as fit, left to right. The rings goals, the challenge, the comparison, the
pick and the buttons are shared with their full-size cards; **Control centre
buttons…** in its settings opens the button editor.

## The cards

Long-press a card > **Module settings** for its options.

| Card | What it shows | Tap | Settings |
| --- | --- | --- | --- |
| Banner | The time and date, and two lines of your own (empty until you type them). Styles: Heading, At a glance (with today's pages, time and streak) and Classic | Flashes the screen clean | Style, top line, bottom line |
| Continue reading | The book you're reading: cover, progress, time left, days of reading and time spent so far | Continue opens the book, Details opens the book menu, `1 / 5 >` shows the next book | How many books to step through |
| Activity rings | Today's pages, minutes and streak as three rings | Reading progress | Daily pages, daily minutes, streak length |
| Week rings | A pages ring and a minutes ring for each day this week, and your daily averages | Reading calendar | Daily pages, daily minutes |
| This week | A bar for each day this week | Reading calendar | Pages or minutes |
| Year goal | Books finished this year against your goal | | Goal, books read outside KOReader |
| Book club | This month's picks, your progress on each, days left, and how much of the club's list you've read | A book opens it | Collection, this month's books, title |
| Month rings | The two rings for every day of the month as a calendar, with your daily averages | Reading calendar | Daily pages, daily minutes |
| Month totals | Books finished, time read and pages read this month | The books figure lists the month's books | |
| Pages per day | A bar for each day of the month, with a line at your daily average | Reading calendar | Pages or time |
| When you read | The part of the day you read most in, a bar for each hour, and the morning, afternoon, evening and night split | | |
| Longest reads (month) | The month's books that took longest, by time or by days | A book opens its details | Longest by, how many |
| Time read by month | Hours read each month this year | A month lists its books | |
| Longest reads (year) | The year's books that took longest, by time or by days | A book opens its details | Longest by, how many |
| Books and pages | Books finished and pages read each month this year, as two lines | A month lists its books | Which pages to count |
| Year in covers | Every cover you finished this year, in order, with the months marked | A cover opens its details | Cover wall or stacked by month |
| Top genres | The genres you finished most this year | | How many |
| Reading heatmap | A square for each day, more strongly coloured the more you read | Reading calendar | |
| Recently finished | The last few books you finished | A cover opens the book menu | How many |
| TBR shelf | A row of covers from one collection | A cover opens the book | Collection, title, line underneath, how many, labels |
| Finish by | One book against a date: days left, pages a day needed, on pace or not | Opens the book | Book, date, label |
| Reading trends | Your last 90 days against your last year, like Apple's Fitness trends (see below) | Reading progress | |
| Monthly challenge | One goal for the month as a ring, how much each day still needs, on pace or not; on a wide card, your running total against the line to the goal | Reading calendar | What it counts, the target |
| Finish forecast | When you'll finish the book you're reading at your recent pace, the others in progress, and how many books your year is on pace for | A book opens it | Books listed |
| This week vs last | Your average a day this week against last week, as a sentence and two bars, like Apple Health | Reading calendar | Week, month or year; time read, pages or both |
| Today's timeline | Each sitting today as a block along the day, and a list of them: when, which book, how long | Reading calendar | |
| Library stats | How many books you own, have read, are reading, have on hold and haven't started | | Count again now |
| Most-read authors | Your top authors, by books finished or by hours read | | By books or time, how many |
| Random pick | A book you haven't started (see below) | Open opens it, Another picks again | How often, where from, genres, authors |
| Quote of the day | One of your highlights, and the book it's from | Opens the book; Another shows a different quote | |
| Quote of the day 2, 3 and 4 | Another random highlight each, never the same as your other quote cards (see below) | Opens the book; Another shows a different quote | |
| Cover calendar | The month's pages, books and time read, then every day of the month with the cover of the book you read most that day (see below) | A day lists its books; a book opens it | Time on each day (shown as it comes) |
| Week in covers | This week's days with their covers and time read, in one row | A day lists its books | Time on each day (shown as it comes) |
| Mini dashboard | One row of small cards for the top of the home screen (see above) | Each small card does what its big one does | The cards, left to right |
| Control centre | Buttons for any action, lit when they're on, and brightness and warmth in ten steps | Each button runs its action; a step sets the light | Buttons (how many, and each one's action, icon and name), brightness and warmth shown or hidden |
| Device | The battery, storage free, the memory KOReader uses, Wi-Fi and the front light (see below) | Opens the battery statistics | Look |

### When tapped

Every card's settings have **When tapped**: keep the card's own action, open
the reading calendar or progress view, or run something else (with Simple
UI, any Quick Action; with Bookshelf, a plugin, a KOReader action or a menu
entry from its action chooser). Buttons on a card, like Continue and
Details, always keep their own job.

### Book club

1. In KOReader, make a collection with "bookclub" in its name (for example
   `bookclub 2026`) and add the club's books to it.
2. Long-press the card > Module settings > **October's books** (it shows the
   current month) and tick the month's picks. The arrows let you set up
   other months ahead of time.
3. Until you tick anything, the card shows the books from the collection
   you're in the middle of.

**Look: Garden** keeps the covers and titles and turns each progress bar
into a stem. A book you haven't started is a little sprout; as you read, the
stem grows to the right with leaves along it and a bud at its tip, and the
faint line ahead shows how far is left. A finished book's stem ends in a
flower, and its cover gets a dragonfly sticker.

### How the rings work

Each ring is a goal. It fills clockwise from the top, and a closed ring means
you met the goal.

- **Activity rings:** outer is pages today against your daily goal, middle is
  minutes today against your daily goal, inner is your streak against 7 days.
- **Week rings** and **Month rings:** a pages ring (outer) and a minutes ring
  (inner) for each day, with a filled centre when you met both goals.

The goals are shared by all three cards; change them in any of their
settings.

### Hearts instead of rings

In the settings of Activity rings, Week rings, Month rings or the Mini
dashboard, **Shape** switches every rings card between **Rings** and
**Hearts** at once.

- Each day is two hearts, one inside the other. Both start as outlines and
  fill up from the bottom like a glass: the **outer heart with pages**, the
  **inner heart with time**. Half full means half the goal, by area.
- A day that's over without meeting your goals gets a **broken heart** on
  Week rings and Month rings. Today never breaks; days still to come are
  grey outlines.
- **A broken heart when you miss:** **Either goal** (the default; a heart
  stays whole only when both are full) or **Both goals** (it breaks only
  when neither is full).
- **Heart colours:** **Pink** (the default) or the card's own colours.
- The Activity rings card shows your streak as text beside the hearts.

### How Reading trends works

Like the Trends in Apple's Fitness app, each figure is your average over the
last 90 days against your average over the last 365, both ending yesterday:

- **Time read** (minutes a day) and **Pages** (pages a day)
- **Reading days** (days a week you read at all)
- **Session length** (minutes per sitting; a sitting ends after a break of
  more than ten minutes)
- **Reading speed** (pages an hour)
- **Books finished** (books a month)

A figure up on your year, or within 3 % of it, goes under **Keep it going**.
Further down, it goes under **Worth a look**, with a tip when there is room.
With less than four months of statistics, or too few sessions or finished
books to compare, it waits under **Needs more data**.

### Monthly challenge

As it comes, the challenge takes turns month by month (pages, then minutes,
then reading days) and sets a target a tenth above your daily rate over the
last three months, for the length of this month. Long-press the card >
Module settings to choose what it counts and to set your own target;
**Use the automatic target** goes back to the picked one.

**Look: Flower** swaps the ring for a peony. It starts as an outline, like a
colouring page, and its 25 petals colour in as you go: the centre first, then
outward ring by ring, clockwise from the top (each petal is 4% of the goal).
A finished flower sparkles. **Neural network** and **Reticle** (Cyber, see
[The Cyber looks](#the-cyber-looks)), and **Hourglass** and **Chess board**
(Dark Academia, see [The Dark Academia looks](#the-dark-academia-looks)) are
the other looks. The Mini dashboard's challenge follows the card.

### Finish forecast

The date is the book's time left (worked out from your reading speed in that
book) divided by your average reading time a day over the last 30 days. A
book with no time left on record uses its pages left and your pages a day
instead. The line along the bottom is where your year is heading at the rate
you have finished books so far.

### Control centre

- Long-press the card > Module settings: pick from 1 to 8 buttons (6 as it
  comes), and tap a button to change its **action** (with Bookshelf: a
  plugin, a KOReader action, a menu entry or a Bookshelf action; with Simple
  UI: a KOReader action or any Quick Action), its **icon** (Bookshelf's icon
  picker, or 37 icons with Simple UI) and its **name**.
- **Use a picture** puts a PNG or JPEG of your own on a button instead of the
  icon. Copy the picture anywhere on your e-reader (a folder such as
  `koreader/icons` keeps them together), then pick it. Square pictures with a
  transparent background look best; any size works. The picture is shown on
  its own, with no tile behind it, and its name turns the accent colour while
  the button is on. **Use the icon instead** goes back.
- Wi-Fi, night mode and the light buttons light up while they're on.
- Tap a step on the brightness or warmth bar to jump to it, or `−` and `+`
  to move one step. Warmth only shows on a device with a warm light.
- To put it on a Dashboard page: long-press the Dashboard > Module settings >
  **Pages and cards**, pick the page, tap **+ Add a row**, and pick Control
  centre.

### Device

- The battery large (green while charging, red at 20% or less), and beside
  it **Storage** (space free, the bar how full it is), **Memory** (what
  KOReader is using, the bar its share of the device's memory), **Wi-Fi**
  (connected, on or off) and **Light** (the front light's level). Storage
  or memory nine-tenths full turns red. In a small card the light goes
  first, then Wi-Fi.
- It reads them once a minute while it's on screen and redraws only when
  something it shows has changed, so it costs no screen updates the rest of
  the time.
- In a tall box (a slot among the books on Bookshelf's shelf) the battery
  goes on top and the rest under it.
- **Look:** Plain, **Hearts** (a heart that empties as the battery runs
  down, with "Full of energy" down to "Needs a snack!", and pastel pills
  that fill with the level), **System monitor** and **Candle** (see the
  Cyber and Dark Academia looks above).

### Lifetime pages

- Every page you've ever turned in KOReader (since its reading statistics
  started counting on this device), in big figures, with "since" the month you started, how many pages a day
  on average since then, and a bar to the next round number ("8,602 to go
  to 20,000").
- Beside it (under it in a tall box): this year's, this month's and this
  week's pages. Today's reading counts straight away, even from a book
  that's still open.
- It counts each page once a day, the way KOReader's statistics do: a page
  read again on another day counts again. The pages from before the last
  year or so are counted once and kept, so it's quick to draw.
- **Look:** Plain, **Hearts** (Cute: the figures in pink, ten hearts that
  fill up towards the next round number, pastel pills), **Data counter**
  (Cyber: the figures in white glitched cyan and red, like the Cyber clock,
  and bars of segments) or **Ledger** (Dark Academia: the figures with a double gilt
  rule, and the periods as ledger lines). Tap it for reading progress.
- There's also **Pages turned**, the same figure as an ornament with no
  card (see Ornaments).

### This week vs last

The figure for this week is your average a day over the days gone by so far.
Today joins in once it has raised the average, so a morning with nothing read
yet doesn't pull the week down. Last week is the whole of last week. Within
3 % either way counts as about the same. In its settings you can compare
this month with last month, or this year with last year, and show time read,
pages or both.

### Random pick

- **A new pick:** every day, every week, every month, or only when you tap
  **Another**. Another always works too.
- **Pick from:** the whole library or one collection (your TBR, say).
- **Only these genres / Only these authors:** tick as many as you like, or
  leave them on Any. The lists come from your books.
- It only picks books you haven't started. In a series it only offers the
  next book you haven't read: six books into eight, it picks the seventh and
  never the eighth. If you're in the middle of a book in that series, the
  series sits it out. If only a later book is in the collection you picked
  from, you get the one you should read first.

### Library stats and Most-read authors

They count the books in your library: Bookshelf's library with Bookshelf,
or the books under KOReader's home folder with Simple UI. A book you've never opened counts as not started. With Bookshelf,
each book counts under the status Bookshelf gives it, so the figures match
Bookshelf's own Shelf size card (a book marked New is not started, whatever
percentage is left in it). The
count is kept for 15 minutes; **Count again now** in Library stats' settings
counts straight away. By books counts the books you've finished; by time
uses KOReader's reading statistics.

### Quote of the day

One highlight a day from the books in your history (with Bookshelf, the day
starts on the same one as Bookshelf's own card). Tap **Another** for a
different one, picked at random: never the one just shown, and never more
than two in a row from the same book while you have others. If you have no highlights yet, highlight
a line while you read.

### Cover calendar

Along the top are the month's pages read, books read and time read. Each day
you read shows the cover of the book you spent longest on that day, with the
time read under it, the next book fanned out behind it when you read two, and
"+1" (or more) for any others. Days you didn't read show just the date, and
today has a bar under its cover. The time can be hidden in the card's
settings.
Tap a day to see every book you read that day, with the time and pages; tap
one to open it. The covers come from KOReader's cover cache, and the books
from the reading statistics, so it covers every day KOReader timed you,
including books you've since finished or deleted (those show their title
instead of a cover). The arrows next to the month's name step back up to
twelve months, together with the Monthly page; **Today** (or the month's
name) comes back to this month.

### More than one quote

**Quote of the day** shows one highlight a day (with Bookshelf, the same one
as Bookshelf's own card). For more quotes on the same page, add
**Quote of the day 2**, **3** and **4**: each one picks a random highlight of
its own every day, never the same one as the other quote cards on screen, and
**Another** on one doesn't change the others. They pick from the highlights in
the books in KOReader's reading history.

### Today's timeline

A sitting ends after a break of more than ten minutes, like in Reading
trends. Each book has its own colour, and the line across the bar is now.

### How When you read works

KOReader's Reading statistics plugin records how long you spend on every
page and when. The card adds that time up by the hour of the day, for the
month the Monthly page is showing. Morning is 5 am to noon, afternoon noon
to 5 pm, evening 5 to 9 pm and night 9 pm to 5 am.

## Colours

Long-press any card > **Look and colours** (in Bookshelf, under Module
settings; with Simple UI, also in Tools > Reading Log). It applies to all
cards:

- **Theme:** White, Dark, Paper, Cyber or Dark Academia, for the Dashboard.
- **Accent colour** and **Second accent:** twelve colours chosen to show well
  on colour e-ink, two neon ones (yellow and cyan) that go with Cyber, and
  oxblood and brass, which go with Dark Academia.
- **Cards on their own:** match the home screen (the default) or framed in
  the theme.
- **Week starts on:** follow KOReader, Monday or Sunday.

Each card's own **Card colour** setting picks plain or tinted, and which of
the two accents leads.

## Remove

Delete the `readinglog.koplugin` folder from KOReader's `plugins` folder (or
switch it off in KOReader's plugin manager), then restart KOReader. Delete
`settings/readinglog.lua` too to forget its settings.
