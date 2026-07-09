-- gitpanel.lua — a small gitui-like status/diff viewer in a floating window.
--
-- Layout (gitui's "Status" tab):
--   ┌───────────────┬────────────────────────────┐
--   │ Unstaged      │                            │
--   │ (worktree)    │                            │
--   ├───────────────┤   Diff of selected file    │
--   │ Staged        │   (drill in to stage hunks)│
--   │ (index)       │                            │
--   └───────────────┴────────────────────────────┘
--
-- Whole-file ops live in the list panes; hunk-level ops live in the diff pane.
-- Status/diff/stage/unstage are driven by `git` directly (fast + robust); hunk
-- staging pipes a one-hunk patch to `git apply --cached`. Committing is
-- delegated to Neogit's commit popup.

local M = {}

M.ns = vim.api.nvim_create_namespace("gitpanel") -- status-char highlights
M.hns = vim.api.nvim_create_namespace("gitpanel_hunk") -- active-hunk marker
M.win = {} -- { unstaged, staged, diff } window handles
M.buf = {} -- { unstaged, staged, diff } buffer handles
M.lists = { unstaged = {}, staged = {} } -- aligned to buffer lines (1-based)
M.focus = "unstaged" -- "unstaged" | "staged" | "diff"
M.selected = nil -- { which, path, untracked } currently shown in the diff pane
M.root = nil
M.aug = nil
M.timer = nil
M.last_key = nil -- hash of last status output, to skip redundant renders
M.return_win = nil -- window to refocus when the panel closes

-- Porcelain XY combinations that mean "unmerged / conflicted".
local CONFLICT = {
	DD = true,
	AU = true,
	UD = true,
	UA = true,
	DU = true,
	AA = true,
	UU = true,
}

local function tc(s)
	return vim.api.nvim_replace_termcodes(s, true, false, true)
end

local function valid(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function notify(msg, level)
	vim.notify("[gitpanel] " .. msg, level or vim.log.levels.INFO)
end

---Run git in the repo root. Returns stdout (string), exit code, stderr.
local function git(args)
	local cmd = { "git" }
	vim.list_extend(cmd, args)
	local res = vim.system(cmd, { cwd = M.root or vim.uv.cwd(), text = true }):wait()
	return res.stdout or "", res.code or 0, res.stderr or ""
end

---Pipe a patch to `git apply`. reverse=true unstages/undoes; cached=false hits
---the worktree instead of the index; recount=true lets git recompute the hunk
---line counts (safety net for hand-built partial patches). Returns code, stderr.
local function git_apply(patch, reverse, cached, recount)
	local cmd = { "git", "apply", "--whitespace=nowarn" }
	if cached ~= false then
		table.insert(cmd, "--cached")
	end
	if reverse then
		table.insert(cmd, "--reverse")
	end
	if recount then
		table.insert(cmd, "--recount")
	end
	local res = vim.system(cmd, { cwd = M.root, stdin = patch, text = true }):wait()
	return res.code or 0, res.stderr or ""
end

local function repo_root()
	local res = vim.system({ "git", "rev-parse", "--show-toplevel" }, { cwd = vim.uv.cwd(), text = true }):wait()
	if res.code ~= 0 then
		return nil
	end
	return vim.trim(res.stdout or "")
end

function M.is_open()
	return valid(M.win.unstaged) and valid(M.win.staged) and valid(M.win.diff)
end

-- ── status ────────────────────────────────────────────────────────────────

---Parse `git status --porcelain=v1 -z` into unstaged/staged file lists.
local function load_status()
	local out = git({ "status", "--porcelain=v1", "-z", "--untracked-files=all" })
	local entries = vim.split(out, "\0", { plain = true })
	local unstaged, staged = {}, {}

	local i = 1
	while i <= #entries do
		local e = entries[i]
		if e == "" then
			break
		end
		local x, y, path = e:sub(1, 1), e:sub(2, 2), e:sub(4)
		-- Rename/copy entries carry the origin path in the next -z field.
		if x == "R" or x == "C" then
			i = i + 1
		end

		local xy = x .. y
		if x == "?" and y == "?" then
			table.insert(unstaged, { path = path, sc = "?", untracked = true })
		elseif CONFLICT[xy] then
			-- Unmerged/conflicted: view-only here, resolve with another tool.
			table.insert(unstaged, { path = path, sc = "!", conflict = true })
		else
			if y ~= " " then
				table.insert(unstaged, { path = path, sc = y })
			end
			if x ~= " " and x ~= "?" then
				table.insert(staged, { path = path, sc = x })
			end
		end
		i = i + 1
	end

	M.lists.unstaged = unstaged
	M.lists.staged = staged
	return out
end

-- ── hunks ─────────────────────────────────────────────────────────────────

---Split the diff buffer into a header (pre-@@ lines) and hunk line ranges.
---@return string[] lines, integer|nil header_end, table[] hunks
local function diff_hunks()
	local lines = vim.api.nvim_buf_get_lines(M.buf.diff, 0, -1, false)
	local header_end
	local hunks = {}
	for idx, l in ipairs(lines) do
		if l:sub(1, 2) == "@@" then
			header_end = header_end or idx
			hunks[#hunks + 1] = { start = idx }
		end
	end
	for h = 1, #hunks do
		hunks[h].stop = hunks[h + 1] and (hunks[h + 1].start - 1) or #lines
	end
	return lines, header_end, hunks
end

local function current_hunk_index(hunks)
	if #hunks == 0 then
		return nil
	end
	local row = vim.api.nvim_win_get_cursor(M.win.diff)[1]
	for idx, h in ipairs(hunks) do
		if row >= h.start and row <= h.stop then
			return idx
		end
	end
	return 1
end

---Build a minimal patch: file header + a single hunk.
local function build_patch(lines, header_end, hunk)
	local out = {}
	for idx = 1, header_end - 1 do
		out[#out + 1] = lines[idx]
	end
	for idx = hunk.start, hunk.stop do
		out[#out + 1] = lines[idx]
	end
	while #out > 0 and out[#out] == "" do
		out[#out] = nil
	end
	return table.concat(out, "\n") .. "\n"
end

---Build a patch that applies ONLY the selected lines of a hunk.
---Diff buffer rows [sel_lo, sel_hi] are the selection. Lines outside it are
---neutralized so they no-op: unselected changes on the side that must keep
---matching become context, the other side's changes are dropped. `reverse`
---mirrors the rule for reverse-apply (unstage / discard).
---@return string|nil patch  nil if no change lines fall in the selection
local function build_selected_patch(lines, header_end, hunk, sel_lo, sel_hi, reverse)
	local os_, _, ns_ = lines[hunk.start]:match("^@@ %-(%d+),?(%d*) %+(%d+),?%d* @@")
	if not os_ then
		return nil
	end
	local body, old_count, new_count, any = {}, 0, 0, false

	local i = hunk.start + 1
	while i <= hunk.stop do
		local l = lines[i]
		local c = l:sub(1, 1)
		if c == "\\" then -- "\ No newline at end of file" — carry with its line
			body[#body + 1] = l
		elseif c == " " then
			body[#body + 1] = l
			old_count = old_count + 1
			new_count = new_count + 1
		else
			local selected = (i >= sel_lo and i <= sel_hi)
			-- On each side, "keep" = emit as-is, "context" = keep but unchanged,
			-- "drop" = omit (also drop a trailing no-newline marker).
			local keep = selected
			local to_context = not selected and ((c == "-" and not reverse) or (c == "+" and reverse))
			if keep then
				body[#body + 1] = l
				any = true
				if c == "+" then
					new_count = new_count + 1
				else
					old_count = old_count + 1
				end
			elseif to_context then
				body[#body + 1] = " " .. l:sub(2)
				old_count = old_count + 1
				new_count = new_count + 1
			else -- drop
				if lines[i + 1] and lines[i + 1]:sub(1, 1) == "\\" then
					i = i + 1
				end
			end
		end
		i = i + 1
	end
	if not any then
		return nil
	end

	local out = {}
	for h = 1, header_end - 1 do
		out[#out + 1] = lines[h]
	end
	out[#out + 1] = string.format("@@ -%d,%d +%d,%d @@", tonumber(os_), old_count, tonumber(ns_), new_count)
	vim.list_extend(out, body)
	while #out > 0 and out[#out] == "" do
		out[#out] = nil
	end
	return table.concat(out, "\n") .. "\n"
end

local function highlight_current_hunk()
	local buf = M.buf.diff
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, M.hns, 0, -1)
	if M.focus ~= "diff" then
		return
	end
	local _, _, hunks = diff_hunks()
	local idx = current_hunk_index(hunks)
	if not idx then
		return
	end
	local h = hunks[idx]
	for l = h.start, h.stop do
		vim.api.nvim_buf_set_extmark(buf, M.hns, l - 1, 0, {
			sign_text = "▌",
			sign_hl_group = "Identifier",
		})
	end
end

-- ── rendering ─────────────────────────────────────────────────────────────

local function sc_hl(it)
	if it.conflict then
		return "DiagnosticError"
	elseif it.untracked or it.sc == "A" then
		return "Added"
	elseif it.sc == "D" then
		return "Removed"
	else
		return "Changed"
	end
end

local function render_list(which)
	local buf = M.buf[which]
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		return
	end
	local items = M.lists[which]
	local lines = {}
	if #items == 0 then
		lines = { "  (none)" }
	else
		for _, it in ipairs(items) do
			lines[#lines + 1] = string.format(" %s  %s", it.sc, it.path)
		end
	end

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
	for idx, it in ipairs(items) do
		vim.api.nvim_buf_set_extmark(buf, M.ns, idx - 1, 1, { end_col = 2, hl_group = sc_hl(it) })
	end
end

---Build a window title as highlighted chunks so the active ● gets its own
---color (GitpanelActive) instead of inheriting grey FloatTitle.
local function title_chunks(active, text)
	if active then
		return { { " ● ", "GitpanelActive" }, { text .. " ", "FloatTitle" } }
	end
	return { { "   " .. text .. " ", "FloatTitle" } }
end

local function set_titles()
	-- The list that the diff currently reflects stays highlighted even while
	-- focus is in the diff pane.
	local active_list = (M.focus == "diff") and (M.selected and M.selected.which) or M.focus
	local defs = {
		unstaged = { win = M.win.unstaged, label = "Unstaged", n = #M.lists.unstaged },
		staged = { win = M.win.staged, label = "Staged", n = #M.lists.staged },
	}
	for which, d in pairs(defs) do
		if valid(d.win) then
			local text = string.format("%s (%d)", d.label, d.n)
			vim.api.nvim_win_set_config(d.win, { title = title_chunks(M.focus == which, text), title_pos = "left" })
			vim.wo[d.win].cursorline = (active_list == which)
		end
	end
	if valid(M.win.diff) then
		local name = M.selected and M.selected.path or ""
		local text = "Diff" .. (name ~= "" and (" — " .. name) or "")
		vim.api.nvim_win_set_config(M.win.diff, { title = title_chunks(M.focus == "diff", text), title_pos = "left" })
		vim.wo[M.win.diff].cursorline = (M.focus == "diff")
	end
end

local function current_file()
	local which = M.focus
	if which ~= "unstaged" and which ~= "staged" then
		return nil
	end
	local items = M.lists[which]
	if #items == 0 then
		return nil
	end
	local line = vim.api.nvim_win_get_cursor(M.win[which])[1]
	return items[line], which
end

---Render M.selected's diff into the diff buffer and reset its view. Callers
---that run while the user is reading/selecting in the diff pane must NOT invoke
---this (it would wipe the cursor/visual selection); use it only right after a
---mutation when we intend to re-render.
local function render_diff()
	local buf = M.buf.diff
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		return
	end
	local sel = M.selected
	local text
	if not sel then
		text = "No changes."
	elseif sel.untracked then
		text = (git({ "diff", "--no-index", "--", "/dev/null", sel.path }))
	elseif sel.which == "staged" then
		text = (git({ "diff", "--cached", "--", sel.path }))
	else
		text = (git({ "diff", "--", sel.path }))
	end
	if text == nil or text == "" then
		text = "(no textual diff)"
	end

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
	vim.bo[buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(buf, M.hns, 0, -1)
	if valid(M.win.diff) then
		vim.api.nvim_win_set_cursor(M.win.diff, { 1, 0 })
	end
end

---Sync the selected file to the focused list's cursor, then render its diff.
local function update_diff()
	if M.focus == "unstaged" or M.focus == "staged" then
		local it = current_file()
		M.selected = it and { which = M.focus, path = it.path, untracked = it.untracked, conflict = it.conflict }
			or nil
	end
	render_diff()
end

-- ── refresh ───────────────────────────────────────────────────────────────

---@param force boolean? re-render even if the status output is unchanged
function M.refresh(force)
	if not M.is_open() then
		return
	end
	local cursors = {}
	for _, which in ipairs({ "unstaged", "staged" }) do
		if valid(M.win[which]) then
			cursors[which] = vim.api.nvim_win_get_cursor(M.win[which])[1]
		end
	end

	local key = load_status()
	if not force and key == M.last_key then
		return
	end
	M.last_key = key

	render_list("unstaged")
	render_list("staged")
	set_titles()

	for _, which in ipairs({ "unstaged", "staged" }) do
		if valid(M.win[which]) then
			local n = math.max(#M.lists[which], 1)
			pcall(vim.api.nvim_win_set_cursor, M.win[which], { math.min(cursors[which] or 1, n), 0 })
		end
	end
	-- Only touch the diff pane when a list drives it. If the user is in the diff
	-- pane (reading or visually selecting lines), leave it untouched so a
	-- background refresh can't wipe their cursor/selection.
	if M.focus ~= "diff" then
		update_diff()
	end
end

-- ── whole-file actions (list panes) ────────────────────────────────────────

local CONFLICT_MSG = "conflicted file — resolve it with <leader>gN (Neogit) or a mergetool"

function M.stage()
	local it = current_file()
	if not it or M.focus ~= "unstaged" then
		return
	end
	if it.conflict then
		notify(CONFLICT_MSG)
		return
	end
	local _, code, err = git({ "add", "-A", "--", it.path })
	if code ~= 0 then
		notify("stage failed: " .. err, vim.log.levels.ERROR)
	end
	M.refresh(true)
end

function M.unstage()
	local it = current_file()
	if not it or M.focus ~= "staged" then
		return
	end
	local _, code, err = git({ "reset", "-q", "--", it.path })
	if code ~= 0 then
		notify("unstage failed: " .. err, vim.log.levels.ERROR)
	end
	M.refresh(true)
end

function M.stage_all()
	git({ "add", "-A" })
	M.refresh(true)
end

function M.unstage_all()
	git({ "reset", "-q" })
	M.refresh(true)
end

function M.discard()
	local it, which = current_file()
	if not it then
		return
	end
	if it.conflict then
		notify(CONFLICT_MSG)
		return
	end
	if vim.fn.confirm(("Discard changes to %s?"):format(it.path), "&Yes\n&No", 2) ~= 1 then
		return
	end
	if it.untracked then
		vim.fn.delete(M.root .. "/" .. it.path)
	elseif which == "staged" then
		git({ "reset", "-q", "--", it.path })
		git({ "restore", "--", it.path })
	else
		git({ "restore", "--", it.path })
	end
	M.refresh(true)
end

function M.open_file()
	local it = (M.focus == "diff") and M.selected or current_file()
	if not it then
		return
	end
	local path = M.root .. "/" .. it.path

	-- From the diff pane, resolve the cursor position to the file line so we
	-- land where we were reading. New-side line = new_start advanced past every
	-- context/added line up to the cursor (deletions don't exist in the file).
	local target
	if M.focus == "diff" then
		local lines, _, hunks = diff_hunks()
		local idx = current_hunk_index(hunks)
		if idx then
			local hunk = hunks[idx]
			local ns = lines[hunk.start]:match("^@@ %-%d+,?%d* %+(%d+)")
			if ns then
				local cur = vim.api.nvim_win_get_cursor(M.win.diff)[1]
				local ln = tonumber(ns) - 1
				for i = hunk.start + 1, math.min(cur, hunk.stop) do
					local c = lines[i]:sub(1, 1)
					if c == " " or c == "+" then
						ln = ln + 1
					end
				end
				target = math.max(ln, 1)
			end
		end
	end

	M.close()
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	if target then
		pcall(vim.api.nvim_win_set_cursor, 0, { target, 0 })
		vim.cmd("normal! zz")
	end
end

function M.commit()
	local ok, neogit = pcall(require, "neogit")
	if not ok then
		notify("neogit not available for commit", vim.log.levels.ERROR)
		return
	end
	neogit.open({ "commit" })
end

-- ── hunk-level actions (diff pane) ─────────────────────────────────────────

---Re-render the diff for M.selected and put the cursor on a hunk. Used after a
---mutation (refresh no longer touches the diff while focus is in it) and when
---entering the diff pane.
local function reselect_hunk(prefer)
	if not valid(M.win.diff) then
		return
	end
	render_diff()
	local _, _, hunks = diff_hunks()
	if #hunks == 0 then
		pcall(vim.api.nvim_win_set_cursor, M.win.diff, { 1, 0 })
	else
		local i = math.min(prefer or 1, #hunks)
		pcall(vim.api.nvim_win_set_cursor, M.win.diff, { hunks[i].start, 0 })
	end
	highlight_current_hunk()
end

function M.stage_hunk()
	local sel = M.selected
	if not sel then
		return
	end
	if sel.conflict then
		notify(CONFLICT_MSG)
		return
	end
	if sel.untracked then
		-- Partial staging of a brand-new file isn't well-defined; stage it whole.
		git({ "add", "--", sel.path })
		M.refresh(true)
		reselect_hunk(1)
		return
	end
	if sel.which ~= "unstaged" then
		notify("this diff is already staged — use u to unstage a hunk")
		return
	end
	local lines, header_end, hunks = diff_hunks()
	local idx = current_hunk_index(hunks)
	if not idx then
		return
	end
	local code, err = git_apply(build_patch(lines, header_end, hunks[idx]), false, true)
	if code ~= 0 then
		notify("stage hunk failed: " .. err, vim.log.levels.ERROR)
		return
	end
	M.refresh(true)
	reselect_hunk(idx)
end

function M.unstage_hunk()
	local sel = M.selected
	if not sel then
		return
	end
	if sel.which ~= "staged" then
		notify("this diff isn't staged — use s to stage a hunk")
		return
	end
	local lines, header_end, hunks = diff_hunks()
	local idx = current_hunk_index(hunks)
	if not idx then
		return
	end
	-- Reverse-apply the staged hunk to the index to remove it.
	local code, err = git_apply(build_patch(lines, header_end, hunks[idx]), true, true)
	if code ~= 0 then
		notify("unstage hunk failed: " .. err, vim.log.levels.ERROR)
		return
	end
	M.refresh(true)
	reselect_hunk(idx)
end

function M.discard_hunk()
	local sel = M.selected
	if not sel then
		return
	end
	if sel.conflict then
		notify(CONFLICT_MSG)
		return
	end
	if sel.which ~= "unstaged" or sel.untracked then
		notify("can only discard hunks of tracked, unstaged changes")
		return
	end
	if vim.fn.confirm(("Discard this hunk in %s?"):format(sel.path), "&Yes\n&No", 2) ~= 1 then
		return
	end
	local lines, header_end, hunks = diff_hunks()
	local idx = current_hunk_index(hunks)
	if not idx then
		return
	end
	-- Reverse-apply to the worktree (no --cached) to drop the change.
	local code, err = git_apply(build_patch(lines, header_end, hunks[idx]), true, false)
	if code ~= 0 then
		notify("discard hunk failed: " .. err, vim.log.levels.ERROR)
		return
	end
	M.refresh(true)
	reselect_hunk(idx)
end

---Apply the visually-selected lines. reverse/cached mirror git_apply.
local function apply_selection(lo, hi, reverse, cached)
	local _, header_end, hunks = diff_hunks()
	local lines = vim.api.nvim_buf_get_lines(M.buf.diff, 0, -1, false)
	local hunk
	for _, h in ipairs(hunks) do
		if lo <= h.stop and hi >= h.start then
			hunk = h
			break
		end
	end
	if not hunk then
		notify("select lines inside a hunk")
		return
	end
	if M.selected and M.selected.conflict then
		notify(CONFLICT_MSG)
		return
	end
	local patch = build_selected_patch(lines, header_end, hunk, lo, hi, reverse)
	if not patch then
		notify("no +/- lines in selection")
		return
	end
	local code, err = git_apply(patch, reverse, cached, true)
	if code ~= 0 then
		notify("apply failed: " .. err, vim.log.levels.ERROR)
		return
	end
	M.refresh(true)
	reselect_hunk(1)
end

---Read the current visual selection's line range (before it collapses).
local function visual_lines()
	local lo, hi = vim.fn.line("v"), vim.fn.line(".")
	if lo > hi then
		lo, hi = hi, lo
	end
	vim.api.nvim_feedkeys(tc("<Esc>"), "nx", false)
	return lo, hi
end

function M.stage_lines()
	local lo, hi = visual_lines()
	local sel = M.selected
	if not sel or sel.which ~= "unstaged" or sel.untracked then
		notify("select lines in an unstaged, tracked file's diff to stage")
		return
	end
	apply_selection(lo, hi, false, true)
end

function M.unstage_lines()
	local lo, hi = visual_lines()
	if not (M.selected and M.selected.which == "staged") then
		notify("select lines in a staged diff to unstage")
		return
	end
	apply_selection(lo, hi, true, true)
end

function M.discard_lines()
	local lo, hi = visual_lines()
	local sel = M.selected
	if not sel or sel.which ~= "unstaged" or sel.untracked then
		notify("can only discard lines of tracked, unstaged changes")
		return
	end
	if vim.fn.confirm(("Discard %d selected line(s) in %s?"):format(hi - lo + 1, sel.path), "&Yes\n&No", 2) ~= 1 then
		return
	end
	apply_selection(lo, hi, true, false)
end

function M.next_hunk()
	local _, _, hunks = diff_hunks()
	local idx = current_hunk_index(hunks)
	if not idx then
		return
	end
	idx = math.min(idx + 1, #hunks)
	vim.api.nvim_win_set_cursor(M.win.diff, { hunks[idx].start, 0 })
	highlight_current_hunk()
end

function M.prev_hunk()
	local _, _, hunks = diff_hunks()
	local idx = current_hunk_index(hunks)
	if not idx then
		return
	end
	idx = math.max(idx - 1, 1)
	vim.api.nvim_win_set_cursor(M.win.diff, { hunks[idx].start, 0 })
	highlight_current_hunk()
end

-- ── focus movement ─────────────────────────────────────────────────────────

function M.focus_pane(which)
	if which ~= "unstaged" and which ~= "staged" then
		return
	end
	if not valid(M.win[which]) then
		return
	end
	M.focus = which
	vim.api.nvim_set_current_win(M.win[which])
	update_diff()
	set_titles()
end

function M.toggle_focus()
	M.focus_pane((M.focus == "unstaged") and "staged" or "unstaged")
end

---Spatial focus movement within the panel. Bound to <C-h/j/k/l> so those keys
---(often global window-nav maps) can't strand the panel by escaping to the
---underlying window.
function M.nav(dir)
	if dir == "h" then
		if M.focus == "diff" then
			M.back_to_list()
		end
	elseif dir == "l" then
		if M.focus == "unstaged" or M.focus == "staged" then
			M.enter_diff()
		end
	elseif dir == "j" then
		if M.focus == "unstaged" then
			M.focus_pane("staged")
		end
	elseif dir == "k" then
		if M.focus == "staged" then
			M.focus_pane("unstaged")
		end
	end
end

function M.enter_diff()
	-- Sync M.selected to the current list cursor before drilling in, so hunk
	-- ops act on the file actually under the cursor regardless of entry path.
	if M.focus == "unstaged" or M.focus == "staged" then
		update_diff()
	end
	if not (M.selected and valid(M.win.diff)) then
		notify("no file selected")
		return
	end
	M.focus = "diff"
	vim.api.nvim_set_current_win(M.win.diff)
	set_titles()
	reselect_hunk(1)
end

function M.back_to_list()
	local which = (M.selected and M.selected.which) or "unstaged"
	if not valid(M.win[which]) then
		which = "unstaged"
	end
	M.focus = which
	vim.api.nvim_buf_clear_namespace(M.buf.diff, M.hns, 0, -1)
	if valid(M.win[which]) then
		vim.api.nvim_set_current_win(M.win[which])
	end
	set_titles()
end

local function scroll_diff(keys)
	return function()
		if valid(M.win.diff) then
			vim.api.nvim_win_call(M.win.diff, function()
				vim.cmd("normal! " .. keys)
			end)
		end
	end
end

-- ── window management ─────────────────────────────────────────────────────

---Geometry for the three panes, sized to the current editor dimensions.
local function compute_layout()
	local cols, rows = vim.o.columns, vim.o.lines
	local W = math.floor(cols * 0.9)
	local H = math.floor(rows * 0.86)
	local top = math.floor((rows - H) / 2)
	local left = math.floor((cols - W) / 2)
	local Lw = math.floor(W * 0.32)
	local Rw = W - Lw - 4
	local Th = math.floor((H - 2) / 2)
	local Bh = (H - 2) - Th - 2
	return {
		unstaged = { relative = "editor", row = top, col = left, width = Lw, height = Th },
		staged = { relative = "editor", row = top + Th + 2, col = left, width = Lw, height = Bh },
		diff = { relative = "editor", row = top, col = left + Lw + 3, width = Rw, height = H - 2 },
	}
end

---Reflow the panes to the current editor size (e.g. after VimResized).
local function relayout()
	if not M.is_open() then
		return
	end
	local L = compute_layout()
	for _, which in ipairs({ "unstaged", "staged", "diff" }) do
		pcall(vim.api.nvim_win_set_config, M.win[which], L[which])
	end
	set_titles() -- win_set_config can drop titles; re-assert them
end

local HELP_LINES = {
	"  gitpanel - keys",
	"",
	"  Lists (Unstaged / Staged)",
	"    s / u         stage / unstage file",
	"    S / U         stage all / unstage all",
	"    x             discard file changes",
	"    <CR> / l      drill into diff (hunk staging)",
	"    <Tab>         switch Unstaged <-> Staged",
	"    o             open file in editor",
	"",
	"  Diff pane",
	"    s / u / x     stage / unstage / discard hunk",
	"    V then s/u/x  stage / unstage / discard selected lines",
	"    ]c / [c       next / prev hunk",
	"    o             open file at this line",
	"    <Tab> / h     back to list",
	"",
	"  Anywhere",
	"    c             commit (Neogit popup)",
	"    r             refresh",
	"    <C-h/j/k/l>   move between panes",
	"    q / <Esc>     close panel",
	"",
	"  Conflicted files are view-only - resolve with <leader>gN.",
	"",
	"  (press ? / q / <Esc> to dismiss this help)",
}

function M.show_help()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, HELP_LINES)
	vim.bo[buf].modifiable = false
	local width = 0
	for _, l in ipairs(HELP_LINES) do
		width = math.max(width, #l)
	end
	width = width + 2
	local height = #HELP_LINES
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2) - 1,
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = " Help ",
		title_pos = "center",
	})
	local function shut()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
	for _, k in ipairs({ "q", "<Esc>", "?", "<CR>" }) do
		vim.keymap.set("n", k, shut, { buffer = buf, nowait = true, silent = true })
	end
end

function M.close()
	if M.closing then
		return
	end
	M.closing = true
	if M.timer then
		M.timer:stop()
		M.timer:close()
		M.timer = nil
	end
	if M.aug then
		pcall(vim.api.nvim_del_augroup_by_id, M.aug)
		M.aug = nil
	end
	for _, which in ipairs({ "unstaged", "staged", "diff" }) do
		if valid(M.win[which]) then
			pcall(vim.api.nvim_win_close, M.win[which], true)
		end
		M.win[which] = nil
	end
	M.buf = {}
	M.selected = nil
	M.last_key = nil
	-- Return focus to wherever we were before the panel opened.
	if valid(M.return_win) then
		pcall(vim.api.nvim_set_current_win, M.return_win)
	end
	M.return_win = nil
	M.closing = false
end

local function make_buf()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].swapfile = false
	return buf
end

local function set_keymaps(buf, kind)
	local function map(lhs, fn, desc)
		vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = "gitpanel: " .. desc })
	end
	map("q", M.close, "close")
	map("<Esc>", M.close, "close")
	map("r", function()
		M.refresh(true)
	end, "refresh")
	map("c", M.commit, "commit (neogit)")
	map("o", M.open_file, "open file in editor")
	map("?", M.show_help, "help")
	-- Spatial nav within the panel — overrides any global <C-hjkl> window maps
	-- so they can't move focus out to the underlying window.
	map("<C-h>", function()
		M.nav("h")
	end, "focus left")
	map("<C-j>", function()
		M.nav("j")
	end, "focus down")
	map("<C-k>", function()
		M.nav("k")
	end, "focus up")
	map("<C-l>", function()
		M.nav("l")
	end, "focus right")

	if kind == "list" then
		map("<Tab>", M.toggle_focus, "switch pane")
		map("<CR>", M.enter_diff, "drill into diff (hunk staging)")
		map("<Right>", M.enter_diff, "drill into diff")
		map("l", M.enter_diff, "drill into diff")
		map("s", M.stage, "stage file")
		map("u", M.unstage, "unstage file")
		map("S", M.stage_all, "stage all")
		map("U", M.unstage_all, "unstage all")
		map("x", M.discard, "discard file changes")
		map("<C-d>", scroll_diff(tc("<C-d>")), "scroll diff down")
		map("<C-u>", scroll_diff(tc("<C-u>")), "scroll diff up")
		map("<C-f>", scroll_diff(tc("<C-f>")), "page diff down")
		map("<C-b>", scroll_diff(tc("<C-b>")), "page diff up")
	else -- diff pane
		local function xmap(lhs, fn, desc)
			vim.keymap.set("x", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = "gitpanel: " .. desc })
		end
		map("<Tab>", M.back_to_list, "back to list")
		map("<Left>", M.back_to_list, "back to list")
		map("h", M.back_to_list, "back to list")
		map("s", M.stage_hunk, "stage hunk")
		map("u", M.unstage_hunk, "unstage hunk")
		map("x", M.discard_hunk, "discard hunk")
		-- Visual selection → line-level staging.
		xmap("s", M.stage_lines, "stage selected lines")
		xmap("u", M.unstage_lines, "unstage selected lines")
		xmap("x", M.discard_lines, "discard selected lines")
		map("]c", M.next_hunk, "next hunk")
		map("[c", M.prev_hunk, "prev hunk")
		map("<C-n>", M.next_hunk, "next hunk")
		map("<C-p>", M.prev_hunk, "prev hunk")
	end
end

function M.open()
	if M.is_open() then
		vim.api.nvim_set_current_win(M.win[M.focus] or M.win.unstaged)
		return
	end
	M.root = repo_root()
	if not M.root then
		notify("not inside a git repository", vim.log.levels.ERROR)
		return
	end
	M.return_win = vim.api.nvim_get_current_win()

	-- Green active-window marker. `default = true` means a GitpanelActive group
	-- you define yourself (e.g. link it to DiagnosticInfo for blue) wins.
	vim.api.nvim_set_hl(0, "GitpanelActive", { link = "DiagnosticOk", default = true })

	local L = compute_layout()
	local common = { style = "minimal", border = "rounded", title_pos = "left" }

	M.buf.unstaged = make_buf()
	M.buf.staged = make_buf()
	M.buf.diff = make_buf()
	vim.bo[M.buf.diff].filetype = "diff"

	M.win.unstaged =
		vim.api.nvim_open_win(M.buf.unstaged, true, vim.tbl_extend("force", common, L.unstaged, { title = " Unstaged " }))
	M.win.staged =
		vim.api.nvim_open_win(M.buf.staged, false, vim.tbl_extend("force", common, L.staged, { title = " Staged " }))
	M.win.diff =
		vim.api.nvim_open_win(M.buf.diff, false, vim.tbl_extend("force", common, L.diff, { title = " Diff " }))
	-- Stable 1-col gutter so the active-hunk marker doesn't shift the layout.
	vim.wo[M.win.diff].signcolumn = "yes:1"

	set_keymaps(M.buf.unstaged, "list")
	set_keymaps(M.buf.staged, "list")
	set_keymaps(M.buf.diff, "diff")

	M.focus = "unstaged"
	M.selected = nil
	M.last_key = nil
	M.refresh(true)
	vim.api.nvim_set_current_win(M.win.unstaged)

	M.aug = vim.api.nvim_create_augroup("GitpanelSession", { clear = true })
	for _, which in ipairs({ "unstaged", "staged" }) do
		vim.api.nvim_create_autocmd("CursorMoved", {
			group = M.aug,
			buffer = M.buf[which],
			callback = function()
				M.focus = which
				update_diff()
			end,
		})
		vim.api.nvim_create_autocmd("WinEnter", {
			group = M.aug,
			buffer = M.buf[which],
			callback = function()
				M.focus = which
				set_titles()
				M.refresh(false)
			end,
		})
	end
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = M.aug,
		buffer = M.buf.diff,
		callback = function()
			if M.focus == "diff" then
				highlight_current_hunk()
			end
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = M.aug,
		pattern = "NeogitStatusRefreshed",
		callback = function()
			M.refresh(true)
		end,
	})
	-- Reflow the panes when the editor is resized.
	vim.api.nvim_create_autocmd("VimResized", {
		group = M.aug,
		callback = relayout,
	})
	-- Closing any one panel window (e.g. via :q) tears down all three.
	vim.api.nvim_create_autocmd("WinClosed", {
		group = M.aug,
		callback = function(args)
			local w = tonumber(args.match)
			if w and (w == M.win.unstaged or w == M.win.staged or w == M.win.diff) then
				vim.schedule(M.close)
			end
		end,
	})
	M.timer = assert(vim.uv.new_timer())
	M.timer:start(
		1500,
		1500,
		vim.schedule_wrap(function()
			if M.is_open() then
				M.refresh(false)
			end
		end)
	)
end

function M.toggle()
	if M.is_open() then
		M.close()
	else
		M.open()
	end
end

return M
