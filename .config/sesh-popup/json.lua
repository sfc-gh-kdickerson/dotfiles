-- Minimal JSON decode for sesh-agent state files (objects, strings, numbers, bool, null, arrays).
local M = {}

local function utf8(code)
  if code < 0x80 then
    return string.char(code)
  elseif code < 0x800 then
    return string.char(
      0xC0 + math.floor(code / 0x40),
      0x80 + code % 0x40
    )
  elseif code < 0x10000 then
    return string.char(
      0xE0 + math.floor(code / 0x1000),
      0x80 + math.floor(code / 0x40) % 0x40,
      0x80 + code % 0x40
    )
  end
  return string.char(
    0xF0 + math.floor(code / 0x40000),
    0x80 + math.floor(code / 0x1000) % 0x40,
    0x80 + math.floor(code / 0x40) % 0x40,
    0x80 + code % 0x40
  )
end

local function skip_ws(s, i)
  while true do
    local c = s:sub(i, i)
    if c == "" then
      return i
    end
    if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then
      return i
    end
    i = i + 1
  end
end

local function parse_string(s, i)
  if s:sub(i, i) ~= '"' then
    return nil, i
  end
  i = i + 1
  local out = {}
  while i <= #s do
    local c = s:sub(i, i)
    if c == '"' then
      return table.concat(out), i + 1
    end
    if c == "\\" then
      local esc = s:sub(i + 1, i + 1)
      local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
      if esc == "u" then
        local hex = s:sub(i + 2, i + 5)
        if not hex:match("^%x%x%x%x$") then
          return nil, i
        end
        local code = tonumber(hex, 16)
        i = i + 6
        if code >= 0xD800 and code <= 0xDBFF
          and s:sub(i, i + 1) == "\\u" then
          local low_hex = s:sub(i + 2, i + 5)
          local low = tonumber(low_hex, 16)
          if low and low >= 0xDC00 and low <= 0xDFFF then
            code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
            i = i + 6
          end
        end
        out[#out + 1] = utf8(code)
      elseif map[esc] then
        out[#out + 1] = map[esc]
        i = i + 2
      else
        return nil, i
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return nil, i
end

local function parse_value(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == '"' then
    return parse_string(s, i)
  end
  if c == "{" then
    local obj = {}
    i = i + 1
    i = skip_ws(s, i)
    if s:sub(i, i) == "}" then
      return obj, i + 1
    end
    while i <= #s do
      local key
      key, i = parse_string(s, i)
      if not key then
        return nil, i
      end
      i = skip_ws(s, i)
      if s:sub(i, i) ~= ":" then
        return nil, i
      end
      i = skip_ws(s, i + 1)
      local val
      val, i = parse_value(s, i)
      obj[key] = val
      i = skip_ws(s, i)
      local sep = s:sub(i, i)
      if sep == "}" then
        return obj, i + 1
      end
      if sep ~= "," then
        return nil, i
      end
      i = skip_ws(s, i + 1)
    end
    return nil, i
  end
  if c == "[" then
    local arr = {}
    i = i + 1
    i = skip_ws(s, i)
    if s:sub(i, i) == "]" then
      return arr, i + 1
    end
    while i <= #s do
      local val
      val, i = parse_value(s, i)
      arr[#arr + 1] = val
      i = skip_ws(s, i)
      local sep = s:sub(i, i)
      if sep == "]" then
        return arr, i + 1
      end
      if sep ~= "," then
        return nil, i
      end
      i = skip_ws(s, i + 1)
    end
    return nil, i
  end
  if s:sub(i, i + 3) == "null" then
    return nil, i + 4
  end
  if s:sub(i, i + 3) == "true" then
    return true, i + 4
  end
  if s:sub(i, i + 4) == "false" then
    return false, i + 5
  end
  local num = s:match("^%-?%d+%.?%d*", i)
  if num then
    return tonumber(num), i + #num
  end
  return nil, i
end

function M.decode(s)
  if not s or s == "" then
    return nil
  end
  local val, i = parse_value(s, 1)
  i = skip_ws(s, i)
  if i <= #s then
    return nil
  end
  return val
end

function M.read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return M.decode(data)
end

return M
