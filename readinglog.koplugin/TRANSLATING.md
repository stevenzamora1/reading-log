# Translating Reading Log

Reading Log follows KOReader's interface language (Settings > Language), read
once at start-up. English, Italian, Spanish, French and Brazilian Portuguese
are included. There is no separate language setting; restart KOReader after
changing the language.

Reading Log uses the language KOReader is actually showing (gettext's
`current_lang`), so it also follows KOReader's automatic, system language. If
that isn't available it uses the saved `language` setting, then English. At
start-up, `crash.log` gets a `[reading-log i18n]` line with the language
asked for, where it came from, the catalog used and the folder it was read
from. If a catalog is missing or broken, a second line says why it fell back
to English.

The translations belong to Reading Log alone. They don't change KOReader's,
Simple UI's or Bookshelf's own translations, and nothing needs installing or
compiling.

## Add a language

1. Copy `readinglog.koplugin/readinglog/locales/es.lua` to `<code>.lua` in the
   same folder, where
   `<code>` is KOReader's language code in lower case (`de.lua`, `pt_br.lua`).
2. Translate the values, never the English keys. Keep `%1`, `%2` and any
   spaces at the start or end of a message: some messages are pieces of a
   longer line (`" of "`, `"Streak "`).
3. Set the day and month names and initials at the top, the
   `thousands_separator`, the `decimal_separator` and `minute_unit`.
4. Plurals: `plurals` gives the forms for an English singular
   (`["book"] = { "libro", "libros" }`). For a language whose plural rule isn't
   "1 is singular", add `plural_index = function(n) ... end` returning the form
   to use (see `fr.lua`, where 0 is singular too).
5. Run `luajit tests/i18n_spec.lua` from the repository root (`tests/` is in the repository, not in the plugin): it checks that
   every message in the code has a translation, with the same `%1`s.
6. Restart KOReader in that language and look at every card, the Dashboard and
   the settings (with Simple UI and with Bookshelf if you can), on a narrow
   card too.

The loader tries the full code and then the language alone: `es_MX` uses
`es.lua`, `pt_BR` uses `pt_br.lua`. `pt.lua` sends Portuguese from Portugal to
the Brazilian file. A message missing from a file is shown in English.

## In the code

Each file uses `local T = A._`. Wrap text shown to the reader in `T("...")`.
For a sentence with values in it, use `A.tr("Quick action: %1", label)`, so a
translator can move `%1`. For counts, `A.plural(n, "book", "books")`. Use
`A.date`, `A.thousands` and `A.decimal` for dates and numbers.

Don't translate settings keys, action IDs, collection names (`Hardcopy`,
`bookclub <year>`), book data or anything the reader types in.

One catalog covers both home screens: a few messages are only shown with one
of them (the goal notes, "Match Simple UI" / "Match Bookshelf"), but they all
live in the same file.
