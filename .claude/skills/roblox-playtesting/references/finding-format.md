# Playtest finding format

Create one record per independently actionable finding.

## Identity

- **Title:** short observed failure, not a guessed cause
- **Type:** defect / design gap / usability / accessibility-localization / performance / data-security / observation
- **Severity:** S1 / S2 / S3 / S4
- **Priority:** separate product decision
- **Status:** new / confirmed / cannot reproduce / blocked / fixed / regression verified

## Environment

- place/universe, build/version, Studio mode;
- client/server context and player count;
- device, viewport, orientation, input;
- profile/config/feature-flag state;
- related system and charter case.

## Reproduction

- **Preconditions:**
- **Steps:** numbered and minimal
- **Expected:** cite the design, acceptance criterion, or stable contract
- **Actual:** directly observed behavior
- **Frequency:** `observed X of Y attempts`
- **First bad step:** earliest point the state diverged

## Evidence

- console messages with timestamps and client/server origin;
- screenshots or captures;
- inspected instance/property/state;
- profiler or scene evidence when relevant;
- raw playtest note or tester quote, clearly attributed;
- comparison with a known-good build when available.

## Impact and scope

- player/data/security impact;
- affected path and estimated audience based only on evidence;
- workaround and its cost;
- regression status;
- adjacent systems worth checking.

## Diagnosis

- **Confirmed cause:** only when demonstrated
- **Suspected cause:** evidence and uncertainty
- **Likely affected files/instances:**
- **Missing evidence:**

## Follow-up

- recommended owner or skill;
- smallest fix validation;
- permanent regression case;
- external configuration or environment needed.

Never include secrets, full private player data, purchase payloads, or unnecessary identifiers in evidence.
