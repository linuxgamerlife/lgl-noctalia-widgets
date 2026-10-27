-- Pure formatter tests.
local mock = dofile("tests/support/mock.luau")
local _ = mock.new({ config = {} })
local format = mock.loadEntry("lib/format.luau")

local function close(actual, expected, epsilon, label)
  assert(type(actual) == "number", label .. ": expected a number, got " .. tostring(actual))
  assert(math.abs(actual - expected) <= epsilon,
    ("%s: expected %.6f, got %.6f"):format(label, expected, actual))
end

close(format.clamp(-4, 0, 10), 0, 0, "clamp low")
close(format.clamp(14, 0, 10), 10, 0, "clamp high")
close(format.clamp(4, 0, 10), 4, 0, "clamp middle")
assert(format.clamp(nil, 3, 9) == 3, "nil clamp fallback")

close(format.round(12.345, 1), 12.3, 1e-9, "round 1")
close(format.round(12.35, 1), 12.4, 1e-9, "round half up")
close(format.round(1234.6, 0), 1235, 1e-9, "round whole")
assert(format.round(nil, 1) == nil, "nil round")

assert(format.trim("  hello \n") == "hello", "trim")
assert(format.trim(nil) == "", "trim nil")

assert(format.number(8.5, 1) == "8.5", "number one decimal")
assert(format.number(32, 0) == "32", "number whole")
assert(format.number(nil, 1) == "—", "number unknown")

assert(format.pct(42.4) == "42%", "pct down")
assert(format.pct(42.5) == "43%", "pct up")
assert(format.pct(0) == "0%", "pct zero")
assert(format.pct(nil) == "—", "pct unknown")

local units = { bps = "B/s", kbps = "KB/s", mbps = "MB/s", gbps = "GB/s" }
assert(format.format_speed(512, units) == "512 B/s", "speed bytes")
assert(format.format_speed(2048, units) == "2.0 KB/s", "speed KB")
assert(format.format_speed(3 * 1024 * 1024, units) == "3.0 MB/s", "speed MB")
assert(format.format_speed(2 * 1024 * 1024 * 1024, units) == "2.0 GB/s", "speed GB")
assert(format.format_speed(-10, units) == "0 B/s", "speed clamps negative")

local size_units = { gb = "GB", tb = "TB" }
assert(format.format_size_gb(512.4, size_units) == "512 GB", "size GB")
assert(format.format_size_gb(1536, size_units) == "1.50 TB", "size TB")
assert(format.format_size_gb(nil, size_units) == "—", "size unknown")

print("FORMAT TEST OK")
