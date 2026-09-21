# How detection works

The app knows Dictation is listening because `DictationIM` says so, on the distributed notification center, by name.

## The signals

`DictationIM` posts four notifications to `CFNotificationCenterGetDistributedCenter()`:

| Name | Meaning | Used for |
| --- | --- | --- |
| `DictationIMNotificationWillStartListening` | About to start | Cancels a pending stop |
| `DictationIMNotificationStartedListening` | Listening | Raises the band |
| `DictationIMNotificationDidEnterDictationMode` | Mode entered | Logged, never acted on |
| `DictationIMNotificationDidExitDictationMode` | Session over | Lowers the band |

`DictationIMNotificationStoppedListening` exists as a string inside the system binary but was never observed to fire. The stop edge is `DidExitDictationMode`.

Observing these needs no entitlement, no TCC grant, no private framework, and no log scraping. `distnoted` delivers them to any process that asks for them by name. The app is therefore able to detect Dictation without asking for a single permission.

## Verified on

macOS 26.6.2 (build 25G83), across two live dictation sessions observed by an unsigned, unentitled command-line binary.

Measured latencies, notification ahead of the audio:

| Edge | Session 1 | Session 2 |
| --- | --- | --- |
| Start | 127ms | 91ms |
| Stop | 93ms | 78ms |

## Why it is a state machine and not a binding

`DidExitDictationMode` is not self-evidently a stop. Both observed sessions emitted one *during the start sequence*, before `StartedListening`. Binding the notification directly to the band would make every session begin with a flash off and on again.

So a stop becomes pending, and a start arriving within 150ms cancels it. That window is a constant, not an adaptive measure; both observed sessions fell well inside it.

## What was ruled out

**`kAudioDevicePropertyDeviceIsRunningSomewhere`** reads `0` for the whole of a dictation session, not merely at the stop. Native Dictation captures through a `corespeechd` audio tap and never opens the default input device, so the property cannot carry either edge.

**`corespeechd` owning the input** holds `kAudioProcessPropertyIsRunningInput` in roughly four-second bursts every 30 to 90 seconds while Dictation is idle, running voice-trigger scoring. Any rule keyed on it false-positives continuously.

**Process presence** is unreliable in both directions. `DictationIM` launched fresh 1.4 seconds before the first observed session rather than running persistently.

**Control Center's own attribution** is `SystemStatus.framework` — `STDataAccessStatusDomain` publishing `STDataAccessAttribution`. It is gated behind the Apple-internal entitlements `com.apple.systemstatus.activityattribution` and `com.apple.systemstatus.domains`, which a third party cannot hold. A closed door rather than a fragility tradeoff, recorded so it is not revisited.

**Microphone attribution** is available publicly, via `kAudioHardwarePropertyProcessObjectList` with `kAudioProcessPropertyIsRunningInput`, since macOS 14.2 and with no TCC grant. It turned out not to be needed: the notification is Dictation-specific by name, so there is nothing to attribute.

## What breaks it, and how you find out

The notification names are undocumented. Apple may rename or withdraw them in any release, and nothing will announce it. The failure is silent and looks exactly like not dictating: no band.

That is what the self-test is for. It asks you to dictate, watches the real detector, and reports whether it saw the start, the stop, and how long each took. Run it from the menu when you suspect something is wrong.

Two other things can produce the same silence, and the menu distinguishes them: the app not running at all, and a session the app saw but that ended long ago. The menu shows when detection last worked end to end.

## Robustness

Distributed notifications are dropped silently when `distnoted`'s queue fills — measured at 94% loss under a 500-post burst, and lossless at any realistic spacing. Dictation is nowhere near that regime, but the failure mode is silent loss rather than delay, so:

- Observers register with `.deliverImmediately`. The block-based Swift API has no suspension-behavior parameter and silently registers as `.coalesce`, which drops all but the last notification while the app is suspended.
- A listening state that stands for thirty minutes is given back unasked. A dropped stop would otherwise leave the band up until the app is quit, which is worse than never showing it, because it claims Dictation is live when it is not.

## Still unverified

Two cases from the plan have not been exercised against a real session:

- Each start path — Globe double-tap, the Fn key, a custom shortcut, the Edit menu. Only one path has been observed, and there is no reason to think `DictationIM` behaves differently across them, but it has not been checked.
- A session where another application holds the microphone throughout. The architecture makes this a non-issue by construction, since nothing in the detection path consults audio, but it has not been confirmed live.
