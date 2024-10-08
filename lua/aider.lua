local helpers = require("helpers")
local M = {}

M.aider_buf = nil

local function NotifyOnExit(code, signal)
	vim.schedule(function()
		vim.notify("Aider process exited with code " .. code .. " and signal " .. signal)
	end)
end

function M.AiderBackground(args, message)
	helpers.showProcessingCue()
	local command = helpers.build_background_command(args, message)
	vim.loop.spawn("bash", {
		args = { "-c", command },
	}, NotifyOnExit)

	vim.notify("Aider started " .. (args or ""))
end

local function OnExit(code, signal)
	if M.aider_buf then
		vim.api.nvim_command("bd! " .. M.aider_buf)
		M.aider_buf = nil
	end
end

function M.AiderOpen(args, window_type)
	window_type = window_type or "vsplit"
	if M.aider_buf and vim.api.nvim_buf_is_valid(M.aider_buf) then
		helpers.open_buffer_in_new_window(window_type, M.aider_buf)
	else
		local command = "aider " .. (args or "")
		helpers.open_window(window_type)
		command = helpers.add_buffers_to_command(command)
		M.aider_job_id = vim.fn.termopen(command, { on_exit = OnExit })
		M.aider_buf = vim.api.nvim_get_current_buf()
	end
end

local function AiderOnBufferOpen(bufnr)
	if not vim.g.aider_buffer_sync or vim.g.aider_buffer_sync == 0 then
		return
	end
	bufnr = tonumber(bufnr)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	local buftype = vim.fn.getbufvar(bufnr, "&buftype")
	if not bufname or bufname:match("^term://") or bufname:match("^oil:") or buftype == "terminal" then
		return
	end
	local relative_filename = vim.fn.fnamemodify(bufname, ":~:.")
	if M.aider_buf and vim.api.nvim_buf_is_valid(M.aider_buf) then
		local line_to_add = "/add " .. relative_filename
		vim.fn.chansend(M.aider_job_id, line_to_add .. "\n")
	end
end

local function AiderOnBufferClose(bufnr)
	if not vim.g.aider_buffer_sync or vim.g.aider_buffer_sync == 0 then
		return
	end
	bufnr = tonumber(bufnr)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	if not bufname or bufname:match("^term://") or bufname:match("^oil:") then
		return
	end
	local relative_filename = vim.fn.fnamemodify(bufname, ":~:.")
	if M.aider_buf and vim.api.nvim_buf_is_valid(M.aider_buf) then
		local line_to_drop = "/drop " .. relative_filename
		vim.fn.chansend(M.aider_job_id, line_to_drop .. "\n")
	end
end

function M.setup(config)
	M.config = config or {}
	M.config.auto_manage_context = M.config.auto_manage_context or true
	M.config.default_bindings = M.config.default_bindings or true

	vim.g.aider_buffer_sync = M.config.auto_manage_context

	if M.config.auto_manage_context then
		vim.api.nvim_command('autocmd BufReadPost * lua require("aider").AiderOnBufferOpen(vim.fn.expand("<abuf>"))')
		vim.api.nvim_command('autocmd BufDelete * lua require("aider").AiderOnBufferClose(vim.fn.expand("<abuf>"))')
		M.AiderOnBufferOpen = AiderOnBufferOpen
		M.AiderOnBufferClose = AiderOnBufferClose
	end

	_G.AiderOpen = M.AiderOpen
	_G.AiderBackground = M.AiderBackground
	_G.aider_background_status = "idle"

	if M.config.default_bindings then
		require("keybindings")
	end
end

return M
