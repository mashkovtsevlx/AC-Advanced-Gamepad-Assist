# Issue review and validation

Reviewed all nine issues, including discussions, on 2026-11-11: four open and five closed in the [repository tracker](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/issues). Changes target `develop`, which includes the existing [vehicle-reference fix](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/pull/59).

## Open issues

| Issue | Result of this change | Remaining evidence needed |
| --- | --- | --- |
| [#57 — Auto Clutch Algorithm](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/issues/57) | Fixes reproducible clutch control failures caused by comparing raw pedal input with car-modified throttle, and failure to engage the clutch when starting the assist while coasting. | In-game testing on the named cars/apps, including launches, TCS, automatic shifts and engine braking. The separate report of jumping straight to top gear has not been reproduced. |
| [#58 — Vibration problem](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/issues/58) | Preserves existing rumble strength on first initialization. Clarifies regular rumble versus impulse-trigger feedback in the guide and UI. | A wired Xbox 360 controller test is still needed. Preserving settings is a demonstrated fix, not proof that it explains every reported vibration failure. |
| [#51 — Front tires straighten during jumps](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/issues/51) | Already addressed in v1.5.5 by [d76c8e3](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/commit/d76c8e3aedf68de9aa3f9dcffb611a1ebc9a0c2c), which removed front-contact fading from the steering correction. Adds regression coverage; no steering behavior changed here. | Verify wheel visuals and landing behavior in an actual drift/jump replay. No new toggle is added. |
| [#55 — Control Tweaks crash](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/issues/55) | Investigated, with no proven fix. The settings-change callback reloads controls, but that fact alone does not establish the crash's cause. No speculative callback changes. | Exact CSP version, affected slider, crash/CSP logs, and the same-slider result with AGA disabled. The separate drift-transition complaint also needs a replay and settings. |

### Clutch correction

The old launch controller used `vehicle.gas` for its RPM target, but compared/subtracted that value against `rawThrottle` each update. Car physics scripts can remap effective throttle, making that difference persist even with an unchanged pedal. Replaying identical pedal/RPM/speed data with different effective throttle could therefore hold the clutch open.

The controller now uses the current assisted pedal input consistently and removes that cross-signal subtraction. RPM feedback still controls launch engagement. Safe wheel-driven engine speed can also engage the clutch without requiring throttle, preserving engine braking when initializing while rolling. Existing anti-stall, manual clutch, handbrake, reverse, encrypted-data and clutch-compatibility protections remain covered by regression cases.

### Rumble correction

On first initialization, the settings reader loaded the existing rumble strength but left the shared UI value at zero. The settings writer subsequently interpreted that zero as a user change and saved it. Initializing the shared value on both installation paths prevents that loss. An already saved zero remains zero; users affected by an earlier installation need to raise **Rumble** manually.

Regular rumble is separate from AGA's impulse-trigger feedback. [Microsoft documents that Xbox 360 controllers lack impulse-trigger motors](https://learn.microsoft.com/en-us/windows/uwp/gaming/gamepad-and-vibration#vibration-and-impulse-triggers). For those controllers, turn both AGA trigger sliders to zero and enable regular rumble. The existing code explicitly silences regular vibration at zero rumble strength, independently of the trigger sliders; that behavior is retained.

## Closed issues

| Issue | Disposition |
| --- | --- |
| [#52 — Force auto-clutch globally](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/issues/52) | Maintainer identified conflicts with custom anti-stall logic and inaccessible/encrypted engine data. The patch retains the compatibility/data checks rather than forcing control without engine information. |
| [#43 — Gas/brake deadzones](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/issues/43) | Reporter resolved locally; not an upstream feature. The corresponding [PR #44 was declined](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/pull/44#issuecomment-2391333861). No new pedal-mapping feature is bundled into these bug fixes. |
| [#40 — Lower-layer rumble access](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/issues/40) | CSP/platform support question. Maintainer explained the native implementation was unavailable and suggested checking Steam Input. No native/Wine fix can be established from this Lua repository. |
| [#35 — Stationary steering](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/issues/35) | Current code and the [configuration guide](../ConfigGuide.md#photo-mode) already provide photo mode, retaining wheel angle while parked. |
| [#30 — Presets unavailable](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/issues/30) | Maintainer attributed this to an older CSP build and required CSP 0.2.0+. That minimum is already checked by the script and advertised in the README. |

## Automated validation

Install LuaJIT, then run from the repository root:

```sh
bash tests/run.sh
```

The runner compiles all production Lua files without executing them, then runs isolated regression processes:

- `test_clutch.lua` executes production `extras.update` and the real PID/smoothing implementation with deterministic vehicle inputs. The original code fails the throttle-remap and rolling-clutch cases.
- `test_rumble.lua` executes production initialization and settings synchronization with in-memory CSP configuration services. The original code loses nonzero first-install rumble.
- `test_airborne.lua` executes production `script.update`, input smoothing and steering correction. It passes current code but fails the actual steering code before the v1.5.5 correction.

Each Lua test accepts an optional source-file path for comparison with a previous revision. CSP APIs and vehicle state are simulated. These tests establish the Lua failures and boundary behavior; they do not simulate engine/wheel dynamics, native vibration output, live calibration, game crashes or wheel rendering.

## In-game checks before marking the PR ready

- On the cars/apps named in [#57](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/issues/57), compare stock and modified throttle behavior during launch, automatic shifts, closed-throttle coasting and stall recovery. Exercise TCS activation/release, reverse, manual clutch, handbrake and keyboard assistance.
- With a nonzero existing rumble setting, start a fresh AGA configuration and verify that rumble stays unchanged. Repeat with saved zero and nonzero settings. On Xbox 360, compare regular rumble with AGA off/on and both trigger sliders at zero; also test a compatible impulse-trigger controller.
- On the same car/track/settings, record a small drift jump and landing for [#51](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/issues/51).
- For [#55](https://github.com/adam10603/AC-Advanced-Gamepad-Assist/issues/55), record the exact Control Tweaks slider and CSP build, compare with AGA disabled, and retain crash/CSP logs. Until there is a reproducible failure or captured crash, this issue remains unresolved.
