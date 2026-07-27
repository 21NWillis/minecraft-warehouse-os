-- mock_cc: minimal ComputerCraft API shim so warehouse modules run under
-- plain Lua for headless testing. Only what recipedb/planner need; extend
-- as more modules come under test.

fs = {}

function fs.combine(a, b)
  if a == "" then return b end
  return (a .. "/" .. b):gsub("//", "/")
end

function fs.exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

function fs.open(path, mode)
  local f = io.open(path, mode)
  if not f then return nil end
  return {
    readLine = function()
      local line = f:read("l")
      return line
    end,
    readAll = function()
      return f:read("a")
    end,
    write = function(text)
      f:write(text)
    end,
    close = function()
      f:close()
    end,
  }
end

http = nil   -- tests always load from disk

os.epoch = function() return math.floor(os.clock() * 1000) end
