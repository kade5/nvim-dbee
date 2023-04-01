---@alias connection_details { name: string, type: string, url: string, id: integer }
---@alias schema { string: string[] }

-- Handler is a wrapper around the go code
-- it is the central part of the plugin and manages connections.
-- almost all functions take the connection id as their argument.
---@class Handler
---@field private connections { integer: connection_details } id - connection mapping
---@field private editor_ui UI ui for the editor
---@field private active_connection integer last called connection
---@field private last_id integer last id number
---@field private page_index integer current page
local Handler = {}

---@param opts? { connections: connection_details[], editor_ui: UI, results_win_cmd: string }
function Handler:new(opts)
  opts = opts or {}

  local win_cmd = opts.results_win_cmd or "bo 15split"

  if not opts.editor_ui then
    print("no editor ui provided to handler")
    return
  end

  local cons = opts.connections or {}

  -- register configuration on go side
  vim.fn.Dbee_update_config(win_cmd)

  local connections = {}
  local last_id = 0
  for id, con in ipairs(cons) do
    if not con.url then
      print("url needs to be set!")
      return
    end
    if not con.type then
      print("no type")
      return
    end

    con.name = con.name or "[empty name]"
    con.id = id

    -- register in go
    vim.fn.Dbee_register_connection(tostring(id), con.url, con.type)

    connections[id] = con
    last_id = id
  end

  -- class object
  local o = {
    connections = connections,
    last_id = last_id,
    editor_ui = opts.editor_ui,
    active_connection = 1,
  }
  setmetatable(o, self)
  self.__index = self
  return o
end

---@param connection connection_details
function Handler:add_connection(connection)
  if not connection.url then
    print("url needs to be set!")
    return
  end
  if not connection.type then
    print("no type")
    return
  end

  local name = connection.name or "[empty name]"

  for _, con in pairs(self.connections) do
    if con.name == name then
      return
    end
  end

  self.last_id = self.last_id + 1
  connection.id = self.last_id

  -- register in go
  vim.fn.Dbee_register_client(tostring(self.last_id), connection.url, connection.type)

  self.connections[self.last_id] = connection
end

---@param id integer connection id
function Handler:set_active(id)
  if not id or self.connections[id] == nil then
    print("no id specified!")
    return
  end
  self.active_connection = id
end

---@return connection_details[] list of connections
function Handler:list_connections()
  local cons = {}
  for _, con in pairs(self.connections) do
    table.insert(cons, con)
  end
  return cons
end

---@return connection_details
---@param id? integer connection id
function Handler:connection_details(id)
  id = id or self.active_connection
  return self.connections[id]
end

---@param query string query to execute
---@param id? integer connection id
function Handler:execute(query, id)
  id = id or self.active_connection

  -- call Go function here
  vim.fn.Dbee_execute(tostring(id), query)

  -- open the first page
  self.page_index = 0
  vim.fn.Dbee_page(tostring(id), tostring(self.page_index))
end

---@param id? integer connection id
function Handler:page_next(id)
  id = id or self.active_connection

  -- go func returns selected page
  self.page_index = vim.fn.Dbee_page(tostring(id), tostring(self.page_index + 1))
end

---@param id? integer connection id
function Handler:page_prev(id)
  id = id or self.active_connection

  self.page_index = vim.fn.Dbee_page(tostring(id), tostring(self.page_index - 1))
end

---@param history_id string history id
---@param id? integer connection id
function Handler:history(history_id, id)
  id = id or self.active_connection
  -- call Go function here
  vim.fn.Dbee_history(tostring(id), history_id)

  -- open the first page
  self.page_index = 0
  vim.fn.Dbee_page(tostring(id), tostring(self.page_index))
end

---@param id? integer connection id
function Handler:list_history(id)
  id = id or self.active_connection

  local h = vim.fn.Dbee_list_history(tostring(id))
  if not h or h == vim.NIL then
    return {}
  end
  return h
end

---@param id? integer connection id
---@return schema
function Handler:schemas(id)
  id = id or self.active_connection
  return vim.fn.Dbee_schema(tostring(id))
end

---@param format "csv"|"json" how to format the result
---@param file string file to write to
---@param id? integer connection id
function Handler:save(format, file, id)
  id = id or self.active_connection
  -- TODO
  vim.fn.Dbee_save(tostring(id))
end

-- TODO
function Handler:editor()
  self.editor_ui:open()
  local winid = self.editor_ui.winid

  vim.api.nvim_win_set_cursor(winid, { 1, 1 })
end

-- TODO
function Handler:editor_exec()
  local vstart = vim.fn.getpos("'<")

  local vend = vim.fn.getpos("'>")

  local start_row = vstart[2]
  local start_col = vstart[3]
  local end_row = vend[2]
  local end_col = vend[3]
  if end_col > 200000 then
    end_col = 20000
  end

  -- or use api.nvim_buf_get_lines
  local lines = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})

  vim.pretty_print(lines)
end

return Handler