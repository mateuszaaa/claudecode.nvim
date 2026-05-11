require("tests.busted_setup")
require("tests.mocks.vim")

describe("ClaudeCodeSend with context text", function()
  local claudecode
  local mock_selection_module
  local mock_server
  local mock_terminal
  local command_callback
  local original_require
  local last_broadcast_params

  before_each(function()
    -- Reset package cache
    package.loaded["claudecode"] = nil
    package.loaded["claudecode.selection"] = nil
    package.loaded["claudecode.terminal"] = nil
    package.loaded["claudecode.server.init"] = nil
    package.loaded["claudecode.lockfile"] = nil
    package.loaded["claudecode.config"] = nil
    package.loaded["claudecode.logger"] = nil
    package.loaded["claudecode.diff"] = nil

    last_broadcast_params = nil

    -- Mock vim API
    _G.vim = {
      api = {
        nvim_create_user_command = spy.new(function(name, callback, opts)
          if name == "ClaudeCodeSend" then
            command_callback = callback
          end
        end),
        nvim_create_augroup = spy.new(function()
          return "test_group"
        end),
        nvim_create_autocmd = spy.new(function()
          return 1
        end),
        nvim_feedkeys = spy.new(function() end),
        nvim_replace_termcodes = spy.new(function(str)
          return str
        end),
        nvim_get_mode = spy.new(function()
          return { mode = "n" }
        end),
      },
      notify = spy.new(function() end),
      log = { levels = { ERROR = 1, WARN = 2, INFO = 3 } },
      deepcopy = function(t)
        local result = {}
        for k, v in pairs(t) do
          result[k] = v
        end
        return result
      end,
      tbl_deep_extend = function(behavior, ...)
        local result = {}
        for _, tbl in ipairs({ ... }) do
          for k, v in pairs(tbl) do
            result[k] = v
          end
        end
        return result
      end,
      fn = {
        mode = spy.new(function()
          return "n"
        end),
        filereadable = spy.new(function()
          return 1
        end),
        isdirectory = spy.new(function()
          return 0
        end),
        getcwd = spy.new(function()
          return "/test/cwd"
        end),
      },
      uv = {
        now = spy.new(function()
          return 1000
        end),
        new_timer = spy.new(function()
          return {
            start = function() end,
            stop = function() end,
            close = function() end,
          }
        end),
      },
      loop = {
        now = spy.new(function()
          return 1000
        end),
        new_timer = spy.new(function()
          return {
            start = function() end,
            stop = function() end,
            close = function() end,
          }
        end),
      },
      schedule_wrap = function(fn)
        return fn
      end,
    }

    -- Mock selection module
    mock_selection_module = {
      send_at_mention_for_visual_selection = spy.new(function(line1, line2, context_text)
        mock_selection_module.last_call = {
          line1 = line1,
          line2 = line2,
          context_text = context_text,
        }
        return true
      end),
    }

    -- Mock terminal module
    mock_terminal = {
      open = spy.new(function() end),
      ensure_visible = spy.new(function() end),
    }

    -- Mock server with broadcast spy
    mock_server = {
      start = function()
        return true, 12345
      end,
      stop = function()
        return true
      end,
      broadcast = spy.new(function(method, params)
        last_broadcast_params = params
        return true
      end),
      get_status = function()
        return {
          running = true,
          client_count = 1,
          clients = {
            { state = "connected", handshake_complete = true },
          },
        }
      end,
    }

    -- Mock other modules
    local mock_lockfile = {
      create = function()
        return true, "/mock/path"
      end,
      remove = function()
        return true
      end,
      generate_auth_token = function()
        return "test-token-1234567890"
      end,
    }

    local mock_config = {
      apply = function(opts)
        return {
          auto_start = false,
          track_selection = true,
          visual_demotion_delay_ms = 200,
          log_level = "info",
          focus_after_send = false,
          connection_wait_delay = 600,
          connection_timeout = 10000,
          queue_timeout = 5000,
          disable_broadcast_debouncing = true,
          diff_opts = {
            layout = "vertical",
            open_in_new_tab = false,
            keep_terminal_focus = false,
            hide_terminal_in_new_tab = false,
            on_new_file_reject = "keep_empty",
          },
          models = {
            { name = "Test Model", value = "test" },
          },
          terminal = {
            split_side = "right",
            split_width_percentage = 50,
            provider = "none",
            show_native_term_exit_tip = true,
            auto_close = false,
            env = {},
          },
          port_range = { min = 10000, max = 65535 },
          env = {},
        }
      end,
    }

    local mock_logger = {
      setup = function() end,
      debug = function() end,
      error = function() end,
      warn = function() end,
      info = function() end,
    }

    local mock_diff = {
      setup = function() end,
    }

    -- Setup require mocks BEFORE requiring claudecode
    original_require = _G.require
    _G.require = function(module_name)
      if module_name == "claudecode.selection" then
        return mock_selection_module
      elseif module_name == "claudecode.terminal" then
        return mock_terminal
      elseif module_name == "claudecode.server.init" then
        return mock_server
      elseif module_name == "claudecode.lockfile" then
        return mock_lockfile
      elseif module_name == "claudecode.config" then
        return mock_config
      elseif module_name == "claudecode.logger" then
        return mock_logger
      elseif module_name == "claudecode.diff" then
        return mock_diff
      else
        return original_require(module_name)
      end
    end

    -- Load and setup claudecode
    claudecode = require("claudecode")
    claudecode.setup({})

    -- Manually set server state for testing
    claudecode.state.server = mock_server
    claudecode.state.port = 12345
  end)

  after_each(function()
    -- Restore original require
    _G.require = original_require
  end)

  describe("ClaudeCodeSend command with context text", function()
    it("should accept optional arguments (nargs = ?)", function()
      -- Find the ClaudeCodeSend command registration
      local calls = _G.vim.api.nvim_create_user_command.calls
      local claudecode_send_call = nil
      for _, call in ipairs(calls) do
        if call.vals[1] == "ClaudeCodeSend" then
          claudecode_send_call = call
          break
        end
      end

      assert(claudecode_send_call ~= nil, "ClaudeCodeSend command should be registered")
      assert(claudecode_send_call.vals[3].nargs == "?", "ClaudeCodeSend should accept optional arguments")
    end)

    it("should pass context text to selection module when args are provided", function()
      assert(command_callback ~= nil, "Command callback should be set")

      -- Simulate command called with range and context text
      local opts = {
        range = 2,
        line1 = 5,
        line2 = 8,
        args = 'Please fix the bug in this function',
      }

      command_callback(opts)

      assert.spy(mock_selection_module.send_at_mention_for_visual_selection).was_called()
      assert.are.same(5, mock_selection_module.last_call.line1)
      assert.are.same(8, mock_selection_module.last_call.line2)
      assert.are.same('Please fix the bug in this function', mock_selection_module.last_call.context_text)
    end)

    it("should not pass context text when args are empty", function()
      assert(command_callback ~= nil, "Command callback should be set")

      local opts = {
        range = 2,
        line1 = 5,
        line2 = 8,
        args = "",
      }

      command_callback(opts)

      assert.spy(mock_selection_module.send_at_mention_for_visual_selection).was_called()
      assert.is_nil(mock_selection_module.last_call.context_text)
    end)

    it("should not pass context text when args are nil", function()
      assert(command_callback ~= nil, "Command callback should be set")

      local opts = {
        range = 2,
        line1 = 5,
        line2 = 8,
      }

      command_callback(opts)

      assert.spy(mock_selection_module.send_at_mention_for_visual_selection).was_called()
      assert.is_nil(mock_selection_module.last_call.context_text)
    end)
  end)

  describe("_broadcast_at_mention with context text", function()
    it("should include text field in broadcast params when context_text is provided", function()
      local success, err = claudecode._broadcast_at_mention(
        "/test/cwd/src/file.lua",
        4,
        10,
        "This function has a bug"
      )

      assert.is_true(success)
      assert.is_nil(err)
      assert.spy(mock_server.broadcast).was_called()
      assert.are.same("at_mentioned", mock_server.broadcast.calls[1].vals[1])
      assert.are.same("src/file.lua", last_broadcast_params.filePath)
      assert.are.same(4, last_broadcast_params.lineStart)
      assert.are.same(10, last_broadcast_params.lineEnd)
      assert.are.same("This function has a bug", last_broadcast_params.text)
    end)

    it("should not include text field when context_text is nil", function()
      local success, err = claudecode._broadcast_at_mention(
        "/test/cwd/src/file.lua",
        4,
        10,
        nil
      )

      assert.is_true(success)
      assert.is_nil(err)
      assert.spy(mock_server.broadcast).was_called()
      assert.are.same("at_mentioned", mock_server.broadcast.calls[1].vals[1])
      assert.is_nil(last_broadcast_params.text)
    end)

    it("should not include text field when context_text is empty string", function()
      local success, err = claudecode._broadcast_at_mention(
        "/test/cwd/src/file.lua",
        4,
        10,
        ""
      )

      assert.is_true(success)
      assert.is_nil(err)
      assert.spy(mock_server.broadcast).was_called()
      assert.is_nil(last_broadcast_params.text)
    end)
  end)

  describe("send_at_mention with context text", function()
    it("should pass context_text to _broadcast_at_mention when connected", function()
      -- Reset broadcast spy
      mock_server.broadcast = spy.new(function(method, params)
        last_broadcast_params = params
        return true
      end)

      local success, err = claudecode.send_at_mention(
        "/test/cwd/src/file.lua",
        4,
        10,
        "test",
        "Fix the memory leak here"
      )

      assert.is_true(success)
      assert.is_nil(err)
      assert.spy(mock_server.broadcast).was_called()
      assert.are.same("Fix the memory leak here", last_broadcast_params.text)
    end)
  end)

  describe("queued mention with context text", function()
    it("should store context_text in the queue and include it when broadcast later", function()
      -- Simulate disconnected state so the mention is queued
      local original_is_connected = claudecode.is_claude_connected
      claudecode.is_claude_connected = function()
        return false
      end

      -- Reset broadcast spy
      mock_server.broadcast = spy.new(function(method, params)
        last_broadcast_params = params
        return true
      end)

      local success, err = claudecode.send_at_mention(
        "/test/cwd/src/file.lua",
        4,
        10,
        "test",
        "Queued context text"
      )

      assert.is_true(success)
      assert.is_nil(err)

      -- Verify the mention was queued with context_text
      assert(claudecode.state.mention_queue ~= nil, "Mention queue should exist")
      assert.are.same(1, #claudecode.state.mention_queue)
      assert.are.same("Queued context text", claudecode.state.mention_queue[1].context_text)

      -- Now simulate connection and process the queue
      claudecode.is_claude_connected = function()
        return true
      end
      claudecode.process_mention_queue()

      -- Verify broadcast includes the text
      assert.spy(mock_server.broadcast).was_called()
      assert.are.same("at_mentioned", mock_server.broadcast.calls[1].vals[1])
      assert.are.same("Queued context text", last_broadcast_params.text)

      -- Restore
      claudecode.is_claude_connected = original_is_connected
    end)
  end)
end)
