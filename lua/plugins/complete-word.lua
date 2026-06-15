-- complete word at primary selection location using vis-menu(1)

-- Identify the word prefix that ends at the cursor.
--
-- Returns the prefix range ([start, cursor)) together with its text, or nil
-- when the character in front of the cursor is not part of a word (for
-- example a separator such as the dot in "vim."), in which case there is no
-- word to complete and the caller should do nothing.
local function word_prefix(win)
	local file = win.file
	local pos = win.selection.pos
	if not pos or pos == 0 then return nil end

	local range = file:text_object_word(pos - 1)
	if not range then return nil end
	-- keep only the part of the word that has actually been typed so far
	if range.finish > pos then range.finish = pos end
	if range.start >= range.finish then return nil end

	local prefix = file:content(range)
	-- A valid prefix consists solely of word characters. text_object_word
	-- returns the surrounding run of *punctuation* when the cursor sits right
	-- after a separator (e.g. "vim."), so anything that is not [%w_] means no
	-- word prefix is present and the regex below would also be unsafe.
	if not prefix or not prefix:match("^[%w_]+$") then return nil end

	return range, prefix
end

-- Write the chosen completion back into the buffer by replacing the typed
-- prefix range with the full candidate word, and return the new cursor
-- position. Kept separate from prefix detection so the candidate is inserted
-- verbatim and we never reason about byte offsets relative to the prefix
-- length (which is what truncated the first character before).
local function replace_with(file, range, word)
	file:delete(range)
	file:insert(range.start, word)
	return range.start + #word
end

vis:map(vis.modes.INSERT, "<C-n>", function()
	local win = vis.win
	local file = win.file

	local range, prefix = word_prefix(win)
	if not range then return end

	vis:feedkeys("<vis-selections-save><Escape><Escape>")
	-- collect words that start with the prefix and have at least one more char
	vis:command("x/\\b" .. prefix .. "\\w+/")
	local candidates = {}
	for sel in win:selections_iterator() do
		local word = file:content(sel.range)
		if word and word ~= "" then
			table.insert(candidates, word)
		end
	end
	vis:feedkeys("<Escape><Escape><vis-selections-restore>")

	if #candidates == 0 then
		-- nothing matched: leave the buffer untouched
		vis.mode = vis.modes.INSERT
		return
	end

	local status, out, err = vis:pipe(table.concat(candidates, "\n"), "sort -u | vis-menu -b")
	if status == 0 and out then
		-- vis-menu echoes the chosen entry followed by a newline
		local word = out:match("^(.-)%s*$")
		if word and word ~= "" and word ~= prefix then
			win.selection.pos = replace_with(file, range, word)
		end
	elseif err then
		vis:info(err)
	end

	-- restore mode to what it was on entry
	vis.mode = vis.modes.INSERT
end, "Complete word in file")
