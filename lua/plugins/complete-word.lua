-- Complete word at primary selection location.
--
-- Responsibilities are split into two phases so that future completion
-- backends can reuse the write-back logic:
--
--   Phase 1 – extract_completion_prefix(pos)
--       Determine what the user has already typed (the prefix) and what
--       regex to use for finding candidates.  Returns separate values for
--       the "word" portion of the prefix (used for suffix calculation) and
--       the full prefix including any separator (unused here but available
--       for callers that need it).
--
--   Phase 2 – apply_completion(pos, word_prefix, selected_candidate)
--       Strip the trailing newline from vis-menu output, compute the
--       suffix that the user has NOT yet typed, and insert it into the
--       buffer at the correct position.

--- Phase 1: extract the word prefix at the cursor position.
--
-- Uses text_object_word to grab the word span, clamps it to the cursor
-- so that only the portion the user has already typed is considered, then
-- strips any leading non-word characters (dots, colons, etc.) so that
-- only the actual word fragment remains.
--
-- @param  file   vis file object
-- @param  pos    cursor byte position (0-based)
-- @return word_prefix  the pure \w+ fragment (e.g. "meth" from "obj.meth")
-- @return full_prefix  the entire typed span including separator (e.g. "obj.meth")
local function extract_completion_prefix(file, pos)
    local range = file:text_object_word(pos > 0 and pos - 1 or pos)
    if not range then return nil, nil end
    if range.finish > pos then range.finish = pos end
    if range.start >= range.finish then return nil, nil end

    local full_prefix = file:content(range)
    if not full_prefix or full_prefix == "" then return nil, nil end

    -- Keep only the trailing \w+ run — this is the real completion stem.
    -- For "obj.meth"  → word_prefix = "meth"
    -- For "hello"     → word_prefix = "hello"
    -- For "vim."      → word_prefix = nil  (nothing to complete after dot)
    local word_prefix = full_prefix:match("[%w_]+$")
    return word_prefix, full_prefix
end

--- Phase 2: compute the suffix and write it into the buffer.
--
-- The suffix is everything in `selected` that comes after `word_prefix`.
-- We strip a possible trailing newline from vis-menu output FIRST, then
-- calculate the suffix — never combine both operations in a single sub()
-- call, because that silently eats the last character when the output
-- format differs from the assumption.
--
-- @param  file          vis file object
-- @param  pos           insertion byte position
-- @param  word_prefix   the \w+ prefix (from extract_completion_prefix)
-- @param  selected      raw string returned by vis:pipe (may have trailing \n)
-- @return true if text was inserted, false otherwise
local function apply_completion(file, pos, word_prefix, selected)
    if not selected or selected == "" then return false end

    -- Step 1: strip exactly one optional trailing newline.
    -- Using gsub("\n$", "") is safe whether or not vis-menu appended \n,
    -- and matches the convention used by complete-filename.lua.
    local candidate = selected:gsub("\n$", "")
    if candidate == "" then return false end

    -- Step 2: compute the suffix the user has not yet typed.
    local suffix = candidate:sub(#word_prefix + 1)
    if suffix == "" then return false end

    -- Step 3: insert and move cursor past the new text.
    file:insert(pos, suffix)
    return true
end

-- Map <C-n> in INSERT mode.
vis:map(vis.modes.INSERT, "<C-n>", function()
    local win  = vis.win
    local file = win.file
    local pos  = win.selection.pos
    if not pos then return end

    -- Phase 1 ----------------------------------------------------------
    local word_prefix, full_prefix = extract_completion_prefix(file, pos)
    if not word_prefix or word_prefix == "" then return end

    -- Transition to NORMAL mode, saving selections so we can restore the
    -- cursor and any multi-selections afterwards.
    vis:feedkeys("<vis-selections-save><Escape><Escape>")

    -- Collect every word in the file that starts with word_prefix.
    -- \b ensures a word-boundary anchor; \w+ extends to the full word.
    vis:command("x/\\b" .. word_prefix .. "\\w+/")

    local candidates = {}
    for sel in win:selections_iterator() do
        local text = file:content(sel.range)
        -- Only keep candidates that are strictly longer than the prefix;
        -- selecting an identical word would insert nothing.
        if text and text ~= "\n" and #text > #word_prefix then
            table.insert(candidates, text)
        end
    end

    vis:feedkeys("<Escape><Escape><vis-selections-restore>")

    -- No usable candidates — fail silently, buffer untouched.
    if #candidates == 0 then
        vis.mode = vis.modes.INSERT
        return
    end

    -- Feed candidates through sort -u | vis-menu.
    local input = table.concat(candidates, "\n")
    local status, out, err = vis:pipe(input, "sort -u | vis-menu -b")

    if status == 0 and out then
        -- Phase 2 ------------------------------------------------------
        if apply_completion(file, pos, word_prefix, out) then
            local suffix = out:gsub("\n$", ""):sub(#word_prefix + 1)
            win.selection.pos = pos + #suffix
        end
    else
        if err then vis:info(err) end
    end

    -- Always restore INSERT mode regardless of outcome.
    vis.mode = vis.modes.INSERT
end, "Complete word in file")
