# Reading Log guide

Every card and setting in one place. For the quick version, see the
[README](../README.md).

The ring designs and the idea of a reading dashboard come from
[u/fishnoogz](https://www.reddit.com/user/fishnoogz/)'s Reddit post.

## Install

1. Connect your e-reader by USB and show hidden folders.
2. Open `.adds/koreader/settings/bookshelf/`. If there is no `micromodules`
   folder inside `bookshelf`, create one.
3. Copy **everything inside** the release's `micromodules` folder (the
   `alm_*.lua` files and the `almanac` folder) into
   `.adds/koreader/settings/bookshelf/micromodules/`.
4. Restart KOReader.

Don't use the Bookshelf plugin's own `micromodules` folder
(`.adds/koreader/plugins/bookshelf.koplugin/micromodules/`). It is replaced
whenever Bookshelf updates.

To update, copy the new files over the old ones. Your layout and settings
are kept.

## Set up the Dashboard

1. Bookshelf menu > Settings > Micro modules: turn on **Full-screen button**.
2. Tap that button, at the bottom right of the home screen.
3. Long-press any module, tap the plus in a circle, and add
   **Reading Log · Dashboard**.
4. Long-press the Dashboard and tap **+** until it doesn't grow any more.
5. Long-press every other module and tap the bin to remove it.

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

### Default or Cute

**Style** in the Dashboard's settings (and in Look and colours on any card)
switches every cute look at once:

- **Cute:** hearts instead of rings, the Monthly challenge as a flower, the
  Book club as a garden, the Year goal as a jar of hearts, the quote cards on
  notebook paper, the cover calendars as polaroids, Continue reading as a
  scrapbook, Reading trends on sticky notes, the charts as book spines and
  hearts, Today's timeline as a sky, and the Finish forecast as a desk
  calendar.
- **Default:** all of them back as they came.

Each card can still be changed on its own afterwards. When some are cute
and some aren't, neither is ticked and the settings say so.

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

Any card can also go on its own in Bookshelf's full-screen view or the home
screen's top area: long-press a module, tap the plus in a circle and pick a
`Reading Log · …` card. On their own the cards use Bookshelf's colours,
including its dark theme.

| | | | |
| --- | --- | --- | --- |
| ![Cards](images/cards-1.png) | ![More cards](images/cards-2.png) | ![Home screen](images/home-1.png) | ![Home screen](images/home-2.png) |

## The Mini dashboard

One row of small cards made for the top of the home screen (Bookshelf's top
panel). Turn on Bookshelf menu > Settings > Micro modules > **In the top panel**,
then long-press a module there, tap the plus in a circle and add
**Reading Log · Mini dashboard**.

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

### When tapped

Every card's settings have **When tapped**: keep the card's own action, open
the reading calendar or progress view, or run anything else (a plugin, a
KOReader action, a menu entry). Buttons on a card, like Continue and
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
A finished flower sparkles. The Mini dashboard's challenge follows the card.

### Finish forecast

The date is the book's time left (worked out from your reading speed in that
book) divided by your average reading time a day over the last 30 days. A
book with no time left on record uses its pages left and your pages a day
instead. The line along the bottom is where your year is heading at the rate
you have finished books so far.

### Control centre

- Long-press the card > Module settings: pick from 1 to 8 buttons (6 as it
  comes), and tap a button to change its **action** (a plugin, a KOReader action, a menu entry,
  a Bookshelf action), its **icon** (from Bookshelf's icon picker) and its
  **name**.
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

They count the books in Bookshelf's library (your home folder, as deep as
Bookshelf looks). A book you've never opened counts as not started. The
count is kept for 15 minutes; **Count again now** in Library stats' settings
counts straight away. By books counts the books you've finished; by time
uses KOReader's reading statistics.

### Quote of the day

It shares Bookshelf's quote of the day, so both show the same highlight.
Tap **Another** for a different one. If you have no highlights yet, highlight
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

**Quote of the day** shares Bookshelf's own quote of the day, so it shows the
same highlight as Bookshelf's card. For more quotes on the same page, add
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

Long-press any card > Module settings > **Look and colours** (applies to all
cards):

- **Theme:** White, Dark or Paper, for the Dashboard.
- **Accent colour** and **Second accent:** twelve colours chosen to show well
  on colour e-ink.
- **Cards on their own:** match Bookshelf (the default) or framed in the
  theme.
- **Week starts on:** follow KOReader, Monday or Sunday.

Each card's own **Card colour** setting picks plain or tinted, and which of
the two accents leads.

## Remove

Delete the `alm_*.lua` files and the `almanac` folder from
`settings/bookshelf/micromodules/`, then restart KOReader.
