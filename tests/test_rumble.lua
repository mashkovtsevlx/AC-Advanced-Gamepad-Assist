-- Run from the repository root: luajit tests/test_rumble.lua
-- Exercise real config initialization and updateConfig() without CSP or motors.
-- An optional argument selects another assist.lua revision for comparison.
local sourceDir = "Advanced Gamepad Assist/extension/lua/joypad-assist/Advanced Gamepad Assist/"
package.path = sourceDir .. "?.lua;" .. package.path
vec3 = function(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
table.nkeys = function(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function upvalue(fn, name)
    for i = 1, math.huge do
        local key, value = debug.getupvalue(fn, i)
        assert(key, "Missing production upvalue: " .. name)
        if key == name then return value end
    end
end

local function fixture(firstInstall, initialRumble)
    local now, writes = 0, {}
    local controlValues = {
        STEER_GAMMA = 1.4, STEER_DEADZONE = 0.12,
        RUMBLE_INTENSITY = initialRumble,
    }
    local noop = function() end
    local sharedEvents, controlsChanged = {}, nil
    -- CSP shared struct numeric fields begin at zero.
    local uiData = {_gameRumble = 0}
    local ini = {
        sections = {},
        get = function(_, section, key, default)
            if section == "X360" and controlValues[key] ~= nil then return controlValues[key] end
            return default
        end,
        set = function(_, _, key, value) controlValues[key] = value end,
        save = noop,
        setAndSave = function(_, section, key, value)
            writes[#writes + 1] = {section = section, key = key, value = value}
            controlValues[key] = value
            return true
        end,
    }
    ac = {
        getPatchVersionCode = function() return 3000 end,
        connect = function() return uiData end,
        StructItem = setmetatable({}, {__index = function() return noop end}),
        INIConfig = {load = function(path)
            if path == "script.ini" then return {sections = firstInstall and {} or {AGA = {}}} end
            return ini
        end},
        findFile = function(path) return path end,
        getFolder = function(id) return id end,
        FolderID = {ScriptConfig = "script", Cfg = "cfg"}, KeyIndex = {},
        storage = function(defaults) return defaults end,
        onSharedEvent = function(name, callback) sharedEvents[name] = callback end,
        onControlSettingsChanged = function(callback) controlsChanged = callback end,
        onRelease = noop, onCarJumped = noop, broadcastSharedEvent = noop,
    }
    car, script = {index = 0, isAIControlled = false}, {}
    package.loaded.extras = {}
    package.loaded.CarPerformanceData = {}
    os.clock = function() return now end
    assert(loadfile(arg[1] or (sourceDir .. "assist.lua")))()
    local updateConfig = upvalue(script.update, "updateConfig")
    return {
        uiData = uiData, values = controlValues, writes = writes,
        update = function() now = now + 1; updateConfig() end,
        controlsChanged = controlsChanged,
        factoryReset = sharedEvents.AGA_factoryReset,
    }
end

local originalClock = os.clock
for _, firstInstall in ipairs({true, false}) do
    for _, initialRumble in ipairs({0.65, 0}) do
        local f = fixture(firstInstall, initialRumble)
        f.update()
        assert(f.values.RUMBLE_INTENSITY == initialRumble,
            "First-install initialization erased the configured game rumble intensity")
        assert(f.uiData._gameRumble == initialRumble, "UI must mirror configured game rumble")

        f.values.RUMBLE_INTENSITY = 0.42
        f.controlsChanged()
        f.update()
        assert(f.uiData._gameRumble == 0.42 and f.values.RUMBLE_INTENSITY == 0.42,
            "Control settings reload must preserve the new rumble intensity")

        f.factoryReset()
        f.update()
        assert(f.values.RUMBLE_INTENSITY == 0.42, "Factory reset must preserve game rumble")
        for _, write in ipairs(f.writes) do
            assert(write.key ~= "RUMBLE_INTENSITY", "Initialization must not rewrite game rumble")
        end

        -- An explicit user edit still persists normally.
        f.uiData._gameRumble = 0.8
        f.update()
        assert(f.values.RUMBLE_INTENSITY == 0.8, "Explicit UI rumble changes must persist")
    end
end
os.clock = originalClock
print("PASS: game rumble preserved on first install, existing install, controls reload and factory reset")
