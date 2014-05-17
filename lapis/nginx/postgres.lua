local concat
do
  local _obj_0 = table
  concat = _obj_0.concat
end
local raw_query, logger
local proxy_location = "/query"
local set_logger
set_logger = function(l)
  logger = l
end
local get_logger
get_logger = function()
  return logger
end
local type, tostring, pairs, select
do
  local _obj_0 = _G
  type, tostring, pairs, select = _obj_0.type, _obj_0.tostring, _obj_0.pairs, _obj_0.select
end
local NULL = { }
local raw
raw = function(val)
  return {
    "raw",
    tostring(val)
  }
end
local is_raw
is_raw = function(val)
  return type(val) == "table" and val[1] == "raw" and val[2]
end
local TRUE = raw("TRUE")
local FALSE = raw("FALSE")
local init_logger
init_logger = function()
  local config = require("lapis.config").get()
  if config.log_queries == false then
    return 
  end
  return set_logger(require("lapis.logging"))
end
local backends = {
  default = function(_proxy)
    if _proxy == nil then
      _proxy = proxy_location
    end
    local parser = require("rds.parser")
    init_logger()
    raw_query = function(str)
      if logger then
        logger.query(str)
      end
      local res, m = ngx.location.capture(_proxy, {
        body = str
      })
      local out, err = parser.parse(res.body)
      if not (out) then
        error(tostring(err) .. ": " .. tostring(str))
      end
      do
        local resultset = out.resultset
        if resultset then
          return resultset
        end
      end
      return out
    end
  end,
  raw = function(fn)
    init_logger()
    do
      raw_query = fn
      return raw_query
    end
  end,
  pgmoon = function()
    local after_dispatch
    do
      local _obj_0 = require("lapis.nginx.context")
      after_dispatch = _obj_0.after_dispatch
    end
    local config = require("lapis.config").get()
    local pg_config = assert(config.postgres, "missing postgres configuration")
    init_logger()
    raw_query = function(str)
      local pgmoon = ngx.ctx.pgmoon
      if not (pgmoon) then
        local Postgres
        do
          local _obj_0 = require("pgmoon")
          Postgres = _obj_0.Postgres
        end
        pgmoon = Postgres(pg_config)
        assert(pgmoon:connect())
        ngx.ctx.pgmoon = pgmoon
        after_dispatch(function()
          return pgmoon:keepalive()
        end)
      end
      if logger then
        logger.query("[PGMOON] " .. tostring(str))
      end
      return pgmoon:query(str)
    end
  end
}
local set_backend
set_backend = function(name, ...)
  if name == nil then
    name = "default"
  end
  return assert(backends[name])(...)
end
local format_date
format_date = function(time)
  return os.date("!%Y-%m-%d %H:%M:%S", time)
end
local append_all
append_all = function(t, ...)
  for i = 1, select("#", ...) do
    t[#t + 1] = select(i, ...)
  end
end
local escape_identifier
escape_identifier = function(ident)
  if type(ident) == "table" and ident[1] == "raw" then
    return ident[2]
  end
  ident = tostring(ident)
  return '"' .. (ident:gsub('"', '""')) .. '"'
end
local escape_literal
escape_literal = function(val)
  local _exp_0 = type(val)
  if "number" == _exp_0 then
    return tostring(val)
  elseif "string" == _exp_0 then
    return "'" .. tostring((val:gsub("'", "''"))) .. "'"
  elseif "boolean" == _exp_0 then
    return val and "TRUE" or "FALSE"
  elseif "table" == _exp_0 then
    if val == NULL then
      return "NULL"
    end
    if val[1] == "raw" and val[2] then
      return val[2]
    end
  end
  return error("don't know how to escape value: " .. tostring(val))
end
local interpolate_query
interpolate_query = function(query, ...)
  local values = {
    ...
  }
  local i = 0
  return (query:gsub("%?", function()
    i = i + 1
    return escape_literal(values[i])
  end))
end
local encode_values
encode_values = function(t, buffer)
  local have_buffer = buffer
  buffer = buffer or { }
  local tuples
  do
    local _accum_0 = { }
    local _len_0 = 1
    for k, v in pairs(t) do
      _accum_0[_len_0] = {
        k,
        v
      }
      _len_0 = _len_0 + 1
    end
    tuples = _accum_0
  end
  local cols = concat((function()
    local _accum_0 = { }
    local _len_0 = 1
    for _index_0 = 1, #tuples do
      local pair = tuples[_index_0]
      _accum_0[_len_0] = escape_identifier(pair[1])
      _len_0 = _len_0 + 1
    end
    return _accum_0
  end)(), ", ")
  local vals = concat((function()
    local _accum_0 = { }
    local _len_0 = 1
    for _index_0 = 1, #tuples do
      local pair = tuples[_index_0]
      _accum_0[_len_0] = escape_literal(pair[2])
      _len_0 = _len_0 + 1
    end
    return _accum_0
  end)(), ", ")
  append_all(buffer, "(", cols, ") VALUES (", vals, ")")
  if not (have_buffer) then
    return concat(buffer)
  end
end
local encode_assigns
encode_assigns = function(t, buffer)
  local join = ", "
  local have_buffer = buffer
  buffer = buffer or { }
  for k, v in pairs(t) do
    append_all(buffer, escape_identifier(k), " = ", escape_literal(v), join)
  end
  buffer[#buffer] = nil
  if not (have_buffer) then
    return concat(buffer)
  end
end
local encode_clause
encode_clause = function(t, buffer)
  local join = " AND "
  local have_buffer = buffer
  buffer = buffer or { }
  for k, v in pairs(t) do
    if v == NULL then
      append_all(buffer, escape_identifier(k), " IS NULL", join)
    else
      append_all(buffer, escape_identifier(k), " = ", escape_literal(v), join)
    end
  end
  buffer[#buffer] = nil
  if not (have_buffer) then
    return concat(buffer)
  end
end
raw_query = function(...)
  local config = require("lapis.config").get()
  local default_backend = config.postgres and config.postgres.backend or "default"
  set_backend(default_backend)
  return raw_query(...)
end
local query
query = function(str, ...)
  if select("#", ...) > 0 then
    str = interpolate_query(str, ...)
  end
  return raw_query(str)
end
local _select
_select = function(str, ...)
  return query("SELECT " .. str, ...)
end
local _insert
_insert = function(tbl, values, ...)
  if values._timestamp then
    values._timestamp = nil
    local time = format_date()
    values.created_at = values.created_at or time
    values.updated_at = values.updated_at or time
  end
  local buff = {
    "INSERT INTO ",
    escape_identifier(tbl),
    " "
  }
  encode_values(values, buff)
  local returning = {
    ...
  }
  if next(returning) then
    append_all(buff, " RETURNING ")
    for i, r in ipairs(returning) do
      append_all(buff, escape_identifier(r))
      if i ~= #returning then
        append_all(buff, ", ")
      end
    end
  end
  return raw_query(concat(buff))
end
local add_cond
add_cond = function(buffer, cond, ...)
  append_all(buffer, " WHERE ")
  local _exp_0 = type(cond)
  if "table" == _exp_0 then
    return encode_clause(cond, buffer)
  elseif "string" == _exp_0 then
    return append_all(buffer, interpolate_query(cond, ...))
  end
end
local _update
_update = function(table, values, cond, ...)
  if values._timestamp then
    values._timestamp = nil
    values.updated_at = values.updated_at or format_date()
  end
  local buff = {
    "UPDATE ",
    escape_identifier(table),
    " SET "
  }
  encode_assigns(values, buff)
  if cond then
    add_cond(buff, cond, ...)
  end
  return raw_query(concat(buff))
end
local _delete
_delete = function(table, cond, ...)
  local buff = {
    "DELETE FROM ",
    escape_identifier(table)
  }
  if cond then
    add_cond(buff, cond, ...)
  end
  return raw_query(concat(buff))
end
local _truncate
_truncate = function(...)
  local tables = concat((function(...)
    local _accum_0 = { }
    local _len_0 = 1
    local _list_0 = {
      ...
    }
    for _index_0 = 1, #_list_0 do
      local t = _list_0[_index_0]
      _accum_0[_len_0] = escape_identifier(t)
      _len_0 = _len_0 + 1
    end
    return _accum_0
  end)(...), ", ")
  return raw_query("TRUNCATE " .. tables .. " RESTART IDENTITY")
end
local parse_clause
do
  local grammar
  local make_grammar
  make_grammar = function()
    local keywords = {
      "where",
      "group",
      "having",
      "order",
      "limit",
      "offset"
    }
    for _index_0 = 1, #keywords do
      local v = keywords[_index_0]
      keywords[v] = true
    end
    local P, R, C, S, Cmt, Ct, Cg
    do
      local _obj_0 = require("lpeg")
      P, R, C, S, Cmt, Ct, Cg = _obj_0.P, _obj_0.R, _obj_0.C, _obj_0.S, _obj_0.Cmt, _obj_0.Ct, _obj_0.Cg
    end
    local alpha = R("az", "AZ", "__")
    local alpha_num = alpha + R("09")
    local white = S(" \t\r\n") ^ 0
    local word = alpha_num ^ 1
    local single_string = P("'") * (P("''") + (P(1) - P("'"))) ^ 0 * P("'")
    local double_string = P('"') * (P('""') + (P(1) - P('"'))) ^ 0 * P('"')
    local strings = single_string + double_string
    local keyword = Cmt(word, function(src, pos, cap)
      if keywords[cap:lower()] then
        return true, cap
      end
    end)
    keyword = keyword * white
    local clause = Ct((keyword * C((strings + (word + P(1) - keyword)) ^ 1)) / function(name, val)
      if name == "group" or name == "order" then
        val = val:match("^%s*by%s*(.*)$")
      end
      return name, val
    end)
    grammar = white * Ct(clause ^ 0)
  end
  parse_clause = function(clause)
    if not (grammar) then
      make_grammar()
    end
    do
      local out = grammar:match(clause)
      if out then
        local _tbl_0 = { }
        for _index_0 = 1, #out do
          local t = out[_index_0]
          local _key_0, _val_0 = unpack(t)
          _tbl_0[_key_0] = _val_0
        end
        return _tbl_0
      end
    end
  end
end
return {
  query = query,
  raw = raw,
  is_raw = is_raw,
  NULL = NULL,
  TRUE = TRUE,
  FALSE = FALSE,
  escape_literal = escape_literal,
  escape_identifier = escape_identifier,
  encode_values = encode_values,
  encode_assigns = encode_assigns,
  encode_clause = encode_clause,
  interpolate_query = interpolate_query,
  parse_clause = parse_clause,
  set_logger = set_logger,
  get_logger = get_logger,
  format_date = format_date,
  set_backend = set_backend,
  select = _select,
  insert = _insert,
  update = _update,
  delete = _delete,
  truncate = _truncate
}
