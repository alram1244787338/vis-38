#!/usr/bin/env lua
-- Standalone unit tests for complete-word.lua string logic.
-- Run: lua test/lua/complete-word-logic.lua

local passed = 0
local failed = 0

local function eq(label, got, expected)
    if got == expected then
        passed = passed + 1
    else
        failed = failed + 1
        io.write(string.format("FAIL  %-40s  expected %q  got %q\n", label, expected, got))
    end
end

---------------------------------------------------------------------------
-- extract_completion_prefix logic: full_prefix:match("[%w_]+$")
---------------------------------------------------------------------------

local function extract_word_prefix(full)
    return full:match("[%w_]+$")
end

eq("simple word",               extract_word_prefix("hel"),           "hel")
eq("full word",                 extract_word_prefix("hello"),         "hello")
eq("dot separator obj.meth",    extract_word_prefix("obj.meth"),      "meth")
eq("dot separator vim.",        extract_word_prefix("vim."),          nil)
eq("colon separator foo:bar",   extract_word_prefix("foo:bar"),       "bar")
eq("arrow separator ptr->mem",  extract_word_prefix("ptr->mem"),      "mem")
eq("slash separator path/to",   extract_word_prefix("path/to"),       "to")
eq("snake_case suffix",         extract_word_prefix("foo_bar"),       "foo_bar")
eq("single char after dot",     extract_word_prefix("obj.m"),         "m")
eq("digits in word",            extract_word_prefix("var123"),        "var123")
eq("trailing underscore",       extract_word_prefix("obj._priv"),     "_priv")

---------------------------------------------------------------------------
-- apply_completion logic: gsub("\n$", "") then sub(#prefix + 1)
---------------------------------------------------------------------------

local function compute_suffix(raw_out, prefix)
    local candidate = raw_out:gsub("\n$", "")
    if candidate == "" then return nil end
    local suffix = candidate:sub(#prefix + 1)
    if suffix == "" then return nil end
    return suffix
end

-- with trailing newline (typical vis-menu output)
eq("hel + hello\\n",        compute_suffix("hello\n",    "hel"),      "lo")
eq("meth + method\\n",      compute_suffix("method\n",   "meth"),     "od")
eq("m + method\\n",         compute_suffix("method\n",   "m"),        "ethod")
eq("complet + complete\\n", compute_suffix("complete\n", "complet"),  "e")

-- without trailing newline (edge case that broke old code)
eq("hel + hello (no \\n)",  compute_suffix("hello",      "hel"),      "lo")
eq("meth + method (no \\n)",compute_suffix("method",     "meth"),     "od")
eq("m + method (no \\n)",   compute_suffix("method",     "m"),        "ethod")

-- candidate == prefix (exact match, should not insert anything)
eq("hello == hello\\n",     compute_suffix("hello\n",    "hello"),    nil)
eq("hello == hello",        compute_suffix("hello",      "hello"),    nil)

-- empty / cancelled
eq("empty string",          compute_suffix("",           "hel"),      nil)
eq("only newline",          compute_suffix("\n",         "hel"),      nil)

-- old code bug reproduction: "hel" + "hello" without \n
-- old: out:sub(4, 4) = "l"  (ate 'o')
-- new: candidate:sub(4) = "lo"
eq("OLD BUG repro (no \\n)",compute_suffix("hello",      "hel"),      "lo")

-- single-char suffix
eq("hell + hello\\n",       compute_suffix("hello\n",    "hell"),     "o")
eq("hell + hello (no \\n)", compute_suffix("hello",      "hell"),     "o")

---------------------------------------------------------------------------
-- summary
---------------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed > 0 and 1 or 0)
