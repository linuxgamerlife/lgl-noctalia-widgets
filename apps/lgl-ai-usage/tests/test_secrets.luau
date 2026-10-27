-- Secret storage modes.

local mock = dofile("tests/support/mock.luau")
local context = mock.new({ config = { key_storage = "local_file" } })
local secrets = require("./lib/secrets.luau")

local stored = nil
secrets.store("openai", "a123", "read-only-key", function(result)
  stored = result
end)
assert(stored and stored.ok, "local key was not stored")

local path = "/tmp/opencode/ai-usage-data/keys/openai.a123.key"
assert(context.files[path] == "read-only-key\n", "local key file contents")

local command = secrets.buildLookupPart("openai", "a123")
assert(command:find("test ! -L", 1, true), "lookup must reject symlinks")
assert(command:find("cat --", 1, true), "lookup must read the local key")
assert(not command:find("read-only-key", 1, true), "key leaked into command")

local cleared = nil
secrets.clear("openai", "a123", function(result)
  cleared = result
end)
assert(cleared and cleared.ok, "local key was not removed")
assert(context.files[path] == nil, "local key file remains")

print("SECRETS TEST OK")
