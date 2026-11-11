-- Run from the repository root: luajit tests/test_airborne.lua
-- An optional argument selects another assist.lua revision for comparison.
-- This executes the real script.update(), input smoothing and steering correction.
-- Only CSP services, vehicle acquisition, calibration and non-steering extras are
-- stubbed; the test cannot verify the game's wheel rendering or landing physics.
local sourceDir = "Advanced Gamepad Assist/extension/lua/joypad-assist/Advanced Gamepad Assist/"
package.path = sourceDir .. "?.lua;" .. package.path

math.NaN = 0 / 0
math.isNaN = function(v) return v ~= v end
math.sign = function(v) return v < 0 and -1 or (v > 0 and 1 or 0) end
math.clamp = function(v, low, high) return math.max(low, math.min(high, v)) end
math.lerp = function(a, b, t) return a + (b - a) * t end
math.lerpInvSat = function(v, a, b) return math.clamp((v - a) / (b - a), 0, 1) end
math.round = function(v, digits)
    local scale = 10 ^ (digits or 0)
    return math.floor(v * scale + 0.5) / scale
end
table.nkeys = function(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
vec3 = function(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end

local function upvalue(fn, name, replacement)
    for i = 1, math.huge do
        local key, value = debug.getupvalue(fn, i)
        assert(key, "Missing production upvalue: " .. name)
        if key == name then
            if replacement ~= nil then debug.setupvalue(fn, i, replacement) end
            return value
        end
    end
end

local function makeRun()
    local noop = function() end
    local ini = {sections = {test = {}}, get = function(_, _, _, default) return default end}
    local uiData = {}
    ac = {
        getPatchVersionCode = function() return 3000 end,
        connect = function() return uiData end,
        StructItem = setmetatable({}, {__index = function() return noop end}),
        INIConfig = {load = function() return ini end},
        findFile = function(path) return path end,
        getFolder = function() return "fixture" end,
        FolderID = {}, KeyIndex = {},
        storage = function(defaults) return defaults end,
        onSharedEvent = noop, onControlSettingsChanged = noop,
        onRelease = noop, onCarJumped = noop, setMessage = noop, debug = noop,
    }
    car = {index = 0, isAIControlled = false, physicsAvailable = true}
    script = {}
    package.loaded.extras = {update = noop}
    package.loaded.CarPerformanceData = {}
    assert(loadfile(arg[1] or (sourceDir .. "assist.lua")))()

    local perfData = {
        updateTargetFrontSlipAngle = noop,
        getTargetFrontSlipAngle = function() return 8 end,
        maxEnginePower = 300, maxRPM = 8000,
    }
    local vData = {
        vehicle = {tractionType = 2, mgukDeliveryCount = 0, rpm = 4000},
        inputData = {steerStickX = 0, steer = 0, brake = 0, gas = 0, rumbleEffects = 0},
        perfData = perfData, wheelbaseFactor = 1, localHVelLen = 25,
        fAxleHVelLen = 25, fAxleLocalVel = vec3(8, 0, 25),
        rAxleLocalVel = vec3(8, 0, 25), localAngularVel = vec3(),
        steeringLockDeg = 40, steeringCurveExponent = 0.95,
        travelDirection = math.deg(math.atan2(8, 25)), frontGrounded = 1,
        totalNdSlip = 0, frontNdSlip = 0, rearNdSlip = 0,
        frontSlipDeg = 0, rearSlipDeg = 0, currentSteeringAngle = 0,
    }
    upvalue(script.update, "getVehicleData", function() return vData end)
    local update = script.update
    return function(grounded, stick)
        vData.frontGrounded = grounded
        vData.inputData.steerStickX = stick or 0
        update(1 / 120)
        return vData.inputData.steer
    end
end

local function near(actual, expected, message)
    assert(math.abs(actual - expected) < 1e-10,
        string.format("%s: expected %.9f, got %.9f", message, expected, actual))
end

-- Warm the filters in a drift with no stick input. The automatic correction
-- should remain turned when front contact fades out, then returns on landing.
local reference, jumping = makeRun(), makeRun()
local takeoff
for _ = 1, 240 do
    takeoff = reference(1)
    near(jumping(1), takeoff, "grounded baseline")
end
assert(math.abs(takeoff) > 0.1, "Fixture must establish visible countersteering")
for frame = 1, 120 do
    local grounded = math.max(0, 1 - frame / 30)
    near(jumping(grounded), reference(1), "front contact loss must not center steering")
end
for frame = 1, 120 do
    near(jumping(math.min(1, frame / 30)), reference(1), "landing continuity")
end

-- Holding the automatic steering component must not freeze manual input.
-- Compare with an identical grounded run to verify both steering directions.
for _, stick in ipairs({-1, 1, 0}) do
    local first, last
    for frame = 1, 120 do
        last = jumping(0, stick)
        first = first or last
        near(last, reference(1, stick), "airborne manual steering response")
    end
    assert(math.abs(last - first) > 0.05, "Manual input must change steering in flight")
end
print("PASS: front-contact loss, landing continuity and manual steering through script.update")
