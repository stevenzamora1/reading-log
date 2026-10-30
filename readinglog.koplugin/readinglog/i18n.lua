-- Reading Log owns its catalogs: do not change KOReader/Bookshelf's gettext
-- domain or process locale. Like KOReader, language changes take effect on restart.
local I = {}
local dir = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local failures = {}

local function log(level, message)
    local ok, logger = pcall(require, "logger")
    if ok and logger and type(logger[level]) == "function" then
        logger[level]("[reading-log i18n] " .. message)
    end
end

local function loadCatalog(code)
    local path = dir .. "/locales/" .. code .. ".lua"
    local chunk, err = loadfile(path)
    if not chunk then failures[#failures + 1] = tostring(err); return nil end
    local ok, catalog = pcall(chunk)
    if ok and type(catalog) == "table" then return catalog end
    failures[#failures + 1] = path .. ": " .. (ok and "catalog must return a table" or tostring(catalog))
end

local function detectLanguage()
    -- gettext has already been initialized by KOReader. Its active language
    -- also covers automatic/system language and runtime overrides, which may
    -- not have a corresponding saved "language" setting.
    local ok, gettext = pcall(require, "gettext")
    if ok and type(gettext) == "table" and type(gettext.current_lang) == "string"
            and gettext.current_lang ~= "" then
        return gettext.current_lang, "gettext"
    end
    if G_reader_settings and G_reader_settings.readSetting then
        local language = G_reader_settings:readSetting("language")
        if type(language) == "string" and language ~= "" then return language, "settings" end
    end
    return "en", "default"
end

local code, source = detectLanguage()
I.requested_language, I.language_source = code, source
-- Accept regional variants (it_IT, it-IT, it_IT.UTF-8) without allowing paths.
code = type(code) == "string" and code:match("^([%a][%a%d_-]*)") or "en"
code = (code or "en"):gsub("-", "_"):lower()
local base = code:match("^([^_]+)")
local english = assert(loadCatalog("en"), "Reading Log: missing English locale")
local catalog, selected
if code == "en" or code == "c" then
    catalog, selected = english, "en"
else
    catalog, selected = loadCatalog(code), code
    if not catalog and base ~= code then catalog, selected = loadCatalog(base), base end
    if not catalog then catalog, selected = english, "en" end
end
I.language = selected
local messages = catalog.messages or {}
log("info", "requested=" .. I.requested_language .. " source=" .. source
    .. " catalog=" .. selected .. " directory=" .. dir .. "/locales")
if selected == "en" and base ~= "en" and code ~= "c" then
    log("warn", "English fallback: " .. table.concat(failures, "; "))
end

-- In the emulator only: every message this language has no entry for.
local miss_log = os.getenv("READINGLOG_I18N_MISSES")
local logged = {}

function I.gettext(message)
    local t = messages[message]
    if t then return t end
    if miss_log and catalog ~= english and not logged[message] then
        logged[message] = true
        local f = io.open(miss_log, "a")
        if f then f:write((tostring(message):gsub("\n", "\\n")), "\n"); f:close() end
    end
    return message
end

-- %1, %2, ... can be reordered by translators. A function replacement keeps
-- percent signs in metadata and user-entered text literal, and never translates it.
function I.format(message, ...)
    local args = { ... }
    return (I.gettext(message):gsub("%%(%d+)", function(index)
        local value = args[tonumber(index)]
        return value == nil and ("%" .. index) or tostring(value)
    end))
end

-- Catalogs may supply plural forms and a plural_index(n) for languages with
-- more than two forms. Missing forms fall back to the English source.
function I.ngettext(one, many, n)
    local index = catalog.plural_index and catalog.plural_index(n) or (n == 1 and 1 or 2)
    local forms = catalog.plurals and catalog.plurals[one]
    if forms and forms[index] then return forms[index] end
    return I.gettext(n == 1 and one or many)
end

I.thousands_separator = catalog.thousands_separator or english.thousands_separator
-- "1 h 5 m": the minutes unit ("min" in most languages)
I.minute_unit = catalog.minute_unit or english.minute_unit or "m"
I.decimal_separator = catalog.decimal_separator or english.decimal_separator

local function names(key) return catalog[key] or english[key] end
function I.monthLetter(month) return names("month_letters")[month] end
function I.dayLetter(wday) return names("day_letters")[wday] end

-- Format numeric directives with os.date; resolve names by calendar index, not
-- by replacing substrings (which can corrupt e.g. March / Mar or escaped %%).
function I.date(fmt, timestamp)
    -- Preserve Bookshelf's date localization for languages not yet in our
    -- catalogs (as well as the existing English/system-locale behavior).
    if catalog == english then
        local value = os.date(fmt, timestamp)
        -- Simple UI version: the host's localizer (KOReader's translations of
        -- the English names), set by init.lua
        if type(I.localize) == "function" then
            local localized, result = pcall(I.localize, value)
            if localized and type(result) == "string" then return result end
            return value
        end
        local ok, localdate = pcall(require, "lib/bookshelf_localdate")
        if ok and localdate and localdate.localize then
            local localized, result = pcall(localdate.localize, value)
            if localized and type(result) == "string" then return result end
        end
        return value
    end
    local t = os.date("*t", timestamp)
    return (fmt:gsub("%%(.)", function(directive)
        if directive == "%" then return "%" end
        if directive == "A" then return names("days")[t.wday] end
        if directive == "a" then return names("short_days")[t.wday] end
        if directive == "B" then return names("months")[t.month] end
        if directive == "b" or directive == "h" then return names("short_months")[t.month] end
        return os.date("%" .. directive, timestamp)
    end))
end

return I
