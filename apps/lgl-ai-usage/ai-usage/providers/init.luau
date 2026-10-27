-- Provider registry. Order is the order shown in the Add account picker.

local M = {}

M.ALL = {
  require("./claude.luau"),
  require("./chatgpt.luau"),
  require("./openai.luau"),
  require("./anthropic.luau"),
  require("./xai.luau"),
  require("./opencodeGo.luau"),
  require("./opencodeZen.luau"),
  require("./minimax.luau"),
  require("./requesty.luau"),
  require("./huggingFace.luau"),
  require("./jetbrains.luau"),
}

function M.find(id)
  for _, provider in ipairs(M.ALL) do
    if provider.id == id then
      return provider
    end
  end
  return nil
end

return M
