---
name: roblox-playtesting
description: Plan, run, observe, reproduce, analyze, and report Roblox gameplay playtests and manual QA sessions. Use for first-time-player experience, tutorials, core-loop comprehension, game feel, feature validation, multiplayer interactions, regression checks, exploratory testing, bug reproduction, structured playtest notes, severity triage, and evidence-backed gameplay QA. Do not use for unit-test-only work, device-layout-only checks, or profiler-only analysis; route those to their specialized skills.
---

# Roblox Playtesting

Test observable player behavior against a clear charter. Preserve raw evidence and separate what happened from why it may have happened.

## Required context

1. Read the applicable `AGENTS.md`, feature design/acceptance criteria, known issues, and relevant implementation.
2. Read [references/test-charter.md](references/test-charter.md) before planning or running a session.
3. Read [references/finding-format.md](references/finding-format.md) before reporting bugs or design findings.
4. Select the correct Studio before any state change. Record place, build/version, Play mode, client/server context, device, and input method.
5. Verify current Studio/platform behavior with `$roblox-docs` when the test depends on an unstable API or workflow.

## Choose the mode

- `plan`: create a focused test charter and case matrix;
- `run`: execute an authorized Studio playtest and collect evidence;
- `analyze`: structure existing notes, logs, screenshots, or recordings;
- `reproduce`: establish deterministic steps, frequency, and minimum trigger;
- `regress`: confirm a reported fix and adjacent behavior without expanding scope.

Do not edit implementation when the user requested only testing or diagnosis.

## Build the charter

Define:

- decision or requirement under test;
- build/place and exact systems in scope;
- player profile: first-time/returning, solo/party, device/input;
- preconditions and synthetic account/profile state;
- critical path, edge paths, interruptions, and recovery paths;
- expected observables and evidence sources;
- stop conditions that protect data or prevent invalid results;
- explicit out-of-scope areas.

Prioritize a small number of high-information cases. Cover normal behavior, boundaries, invalid input, reset/death, disconnect/rejoin, duplicate actions, and concurrent players when relevant.

## Run safely in Studio

1. Confirm the correct active Studio and DataModel state.
2. Avoid production DataStore, purchase, badge, entitlement, analytics, and moderation side effects. Use existing test seams or a test place; do not invent unsafe bypasses.
3. Set device simulation before Play when device behavior matters.
4. Start the minimum appropriate Play mode and record the initial console state.
5. Follow the charter steps exactly before exploratory deviations.
6. Capture screenshots, console output, actual GUI/instance state, timestamps, and client/server observations at the failure point.
7. Repeat suspected defects enough to estimate frequency and isolate the minimum trigger.
8. Stop Play and restore simulator/orientation/temporary test state even after failure.

Never claim a multiplayer, persistence, purchase, or cross-server path passed when the environment did not actually exercise it.

## Observe player experience

For first-time or design-focused sessions, record:

- whether the goal and controls were understood without explanation;
- time and actions required to reach the first meaningful outcome;
- confusion, hesitation, repeated mistakes, and abandoned actions;
- moments of delight, mastery, or clear feedback;
- pacing, difficulty, and decision quality;
- features discovered versus missed;
- points where UI, audio, VFX, camera, or world cues changed behavior;
- accessibility, localization, device, and input barriers.

Do not turn one tester's preference into a universal conclusion. Label sample size and tester context.

## Classify findings

Use [references/finding-format.md](references/finding-format.md). Keep separate:

- `DEFECT`: behavior contradicts a requirement or stable platform contract;
- `DESIGN GAP`: observed behavior is internally consistent but harms the intended experience;
- `USABILITY`: the player cannot discover, understand, or operate the feature reliably;
- `ACCESSIBILITY/LOCALIZATION`: input, motion, cue, text, or language barrier;
- `PERFORMANCE`: measured responsiveness or stability issue;
- `DATA/SECURITY`: persistence, authority, purchase, privacy, or exploit risk;
- `OBSERVATION`: useful evidence without enough basis for a verdict.

Assign severity from player/data impact and scope, not annoyance alone:

- `S1 Critical`: data loss/corruption, security/entitlement failure, crash loop, or experience broadly unusable;
- `S2 Major`: critical path blocked or materially wrong with no reasonable workaround;
- `S3 Moderate`: important degradation with a workaround or limited scope;
- `S4 Minor`: cosmetic/polish issue with little functional impact.

Keep priority separate; business order is not the same as severity.

## Analyze and report

1. Preserve raw notes and quote/paraphrase accurately.
2. Map each finding to a charter case or mark it exploratory.
3. Compare expected and actual behavior using design/code/platform evidence.
4. State frequency as observed counts, not unsupported percentages.
5. Separate confirmed cause from suspected cause.
6. Turn fixes into new regression cases.
7. Summarize the top player-impact risks and highest-value next tests.

Route specialized evidence:

- deterministic ModuleScript behavior -> `$roblox-unit-testing`;
- responsive layout, safe areas, or device comparisons -> `$roblox-device-testing`;
- frame-time spikes -> `$roblox-performance-profiling`;
- scene/memory composition -> `$roblox-scene-analysis`;
- economy/progression outcomes -> `$roblox-game-balance`.

## Output

Report session metadata, charter coverage, passed/failed/blocked/not-run cases, findings by severity and type, raw evidence locations, environment limitations, cleanup status, and recommended regressions. A test is `blocked` rather than failed when the required environment or external configuration was unavailable.

## References

- [Test charter](references/test-charter.md): session plan, case matrix, and result summary.
- [Finding format](references/finding-format.md): reproducible defect and playtest-observation record.
