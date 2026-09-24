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

## A start is not raised until it is listening

`WillStartListening` announces a start that may never happen. On 2026-09-24 every Dictation start for
forty seconds reached `WillStartListening` and stopped: `DictationIM` logged `IMKServer Stall detected`
about 6 seconds after each one, blocked on the target app — the Claude app, 1.2 seconds after an
archive — answering where the insertion point was. The HUD hung and `StartedListening` never
arrived. The band was raised on `WillStartListening` at the time, so it stayed up over a microphone
that was not live, which read as the band and the shortcut breaking Dictation. The band now waits for
`StartedListening`; `WillStartListening` only cancels a pending stop.

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

## Verifying the overlay

The band cannot be checked with a screenshot. It is confirmed visible on screen, but it does not appear in a `screencapture`, and that held with the capture opt-out removed and with the window level lowered to `.floating`. Whatever excludes it is not `sharingType` and not the window level.

So the only way to check the overlay is to look at it:

```bash
/Applications/DictationGlow.app/Contents/MacOS/dictation-glow --show-band 6
```

A capture coming back without the band proves nothing. Do not treat an empty screenshot as evidence the overlay is broken.

## Driving a session without dictating

The app is waiting on notifications, not on a microphone, so anything that can post them can put the band up. That is how the overlay gets exercised against a copy already running, including the one launched at login:

```swift
DistributedNotificationCenter.default().postNotificationName(
  Notification.Name("DictationIMNotificationStartedListening"),
  object: nil, userInfo: nil, deliverImmediately: true)
```

`DictationIMNotificationDidExitDictationMode` takes it down again. Every running instance answers, so kill the strays first or the results are incoherent.

**Leave a second between a synthesized stop and the next start.** The stop is held for `EdgeMachine.coalescingWindow` before it is acted on, so one posted at the tail of a test lands inside the session the next test just started and takes the band down under it. That reads as the band failing to stay up, and is only the previous test arriving late.

## Coverage

Confirmed against real dictation sessions: every start path — Globe double-tap, the Fn key, a custom shortcut, the Edit menu — and a session where another application held the microphone throughout. Detection behaves the same in all of them, which is what the architecture predicts: nothing in the detection path reads audio, and every start path goes through the same `DictationIM`.
