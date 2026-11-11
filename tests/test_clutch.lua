-- Runs the production extras.update and AGALib PID/smoothing outside CSP.
-- From the repository root: luajit tests/test_clutch.lua [path/to/extras.lua]
local sourceDir = 'Advanced Gamepad Assist/extension/lua/joypad-assist/Advanced Gamepad Assist/'
package.path = sourceDir .. '?.lua;' .. package.path

math.clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end
math.sign = function(x) return x < 0 and -1 or (x > 0 and 1 or 0) end
math.lerp = function(a, b, t) return a + (b - a) * t end
math.lerpInvSat = function(x, a, b) return math.clamp((x - a) / (b - a), 0, 1) end
math.isNaN = function(x) return x ~= x end
table.clear = function(t) for k in pairs(t) do t[k] = nil end end
car = { index = 0 }
ac = { onSharedEvent = function() end, onCarJumped = function() end,
    setMessage = function() end }

local function scenario(options)
    options = options or {}
    package.loaded.extras = nil -- Each replay starts with independent controller state.
    local extras = arg[1] and dofile(arg[1]) or require 'extras'
    local speed = options.speed or 0.25
    local rpm = options.rpm or 5500
    local gas = options.gas or 1
    local gear = options.gear or 1
    local v = { vehicle = {
        tractionType = 2, gear = gear, gearCount = 6, clutch = 0.00069,
        rpm = rpm, gas = options.vehicleGas or 0, brake = options.brake or 0,
        handbrake = options.handbrake or 0,
        acceleration = { z = 0 }, wheels = {}, tractionControlInAction = false
    }, inputData = {}, cPhys = { gearRatio = gear * 3 }, localVel = { z = speed },
        localHVelLen = speed, localWheelVelocities = {}, perfData = {
            idleRPM = 1000, RPMRange = 6000, brokenEngineIni = options.brokenEngineIni,
            getNormalizedRPM = function() return math.lerpInvSat(rpm, 1000, 7000) end,
            getAbsoluteRPM = function(_, n) return 1000 + n * 6000 end,
            getDrivetrainRatio = function() return gear * 10 end
        } }
    for i = 0, 3 do
        v.vehicle.wheels[i] = { tyreRadius = 0.3, angularSpeed = speed / 0.3 }
        v.localWheelVelocities[i] = { z = speed }
    end
    local ui = { autoClutch = true, autoShiftingMode = 0,
        triggerFeedbackL = 0, triggerFeedbackR = 0 }
    -- Sample CSP's clutch compatibility probe. Its output is observed next frame.
    extras.update(v, ui, 0, 0.01)
    v.vehicle.clutch = options.incompatibleClutch and 1 or v.inputData.clutch
    for _ = 1, 300 do
        v.inputData = { gas = gas, brake = options.brake or 0,
            handbrake = options.handbrake or 0,
            clutch = options.manualClutch or 1 }
        extras.rawThrottle = options.rawThrottle or gas
        extras.update(v, ui, 0, 0.01)
        v.vehicle.clutch = options.incompatibleClutch and 1 or v.inputData.clutch
    end
    return v.inputData.clutch
end

local failed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then print('PASS ' .. name) else
        print('FAIL ' .. name .. ': ' .. tostring(err))
        failed = failed + 1
    end
end
local function engaged(value)
    assert(value > 0.99, ('expected engaged clutch, got %.6f'):format(value))
end

test('modified car throttle does not hold a high-rev launch clutch open', function()
    engaged(scenario { gas = 1, vehicleGas = 0 })
end)
test('launch controller is independent of car throttle remapping', function()
    local normal = scenario { gas = 0.8, vehicleGas = 0.8, rpm = 3000 }
    local remapped = scenario { gas = 0.8, vehicleGas = 0.04, rpm = 3000 }
    assert(math.abs(normal - remapped) < 1e-8,
        ('same pedal/RPM/speed changed clutch from %.6f to %.6f'):format(normal, remapped))
end)
test('rolling with closed throttle retains engine braking', function()
    engaged(scenario { gas = 0, vehicleGas = 0, speed = 20, rpm = 4500 })
end)
test('stationary at idle keeps anti-stall clutch open', function()
    assert(scenario { gas = 0, vehicleGas = 0, speed = 0, rpm = 1000 } < 0.01)
end)
test('rolling against the selected gear keeps reverse protection', function()
    assert(scenario { gas = 0, vehicleGas = 0, speed = -20, rpm = 4500 } < 0.01)
end)
test('manual clutch can still disengage a rolling car', function()
    assert(scenario { gas = 0, speed = 20, rpm = 4500, manualClutch = 0 } < 0.01)
end)
test('braking while rolling retains engine braking', function()
    engaged(scenario { gas = 0, speed = 20, rpm = 4500, brake = 0.5 })
end)
test('reverse gear engages when rolling backwards safely', function()
    engaged(scenario { gear = -1, gas = 0, speed = -20, rpm = 4500 })
end)
test('neutral keeps the clutch open', function()
    assert(scenario { gear = 0, gas = 0, speed = 0, rpm = 1000 } < 0.01)
end)
test('handbrake still disengages the driven rear wheels', function()
    assert(scenario { gas = 0, speed = 20, rpm = 4500, handbrake = 1 } < 0.01)
end)
test('launch uses assisted keyboard throttle rather than raw throttle', function()
    -- A keyboard helper has reduced raw throttle from 1 to 0.1. Car scripts
    -- can independently remap the reported gas, without changing that input.
    engaged(scenario { gas = 0.1, rawThrottle = 1, vehicleGas = 1, rpm = 3000 })
    engaged(scenario { gas = 0.1, rawThrottle = 1, vehicleGas = 0.04, rpm = 3000 })
end)
test('encrypted engine data still leaves clutch to the game', function()
    engaged(scenario { brokenEngineIni = true })
end)
test('incompatible clutch control still leaves clutch to the game', function()
    engaged(scenario { incompatibleClutch = true })
end)
assert(failed == 0, failed .. ' clutch regression(s) failed')
