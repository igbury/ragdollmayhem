# Myth encounters: checkpoint, 2026-11-16

Reference reviewed: all 401 extracted frames at 0.4-second intervals, in 17 sequential contact sheets, with full-resolution checks of the cyclops and weapon catalog. Original video: `2026-11-16 19-17-30.mp4` (160.22 seconds). Video/images remain outside the repository.

| Reference time | Observed feature | Implementation |
| --- | --- | --- |
| 7.6–13.2 s | Map choice and directly accessible test area | Preserve current menu/maps; add Myth Yard adjoining the arena's north edge |
| 14–24 s | First-person pistol, muzzle feedback, target indicators | Preserve existing sway/recoil/FX; connect server-confirmed monster hit feedback |
| 24.8–38 s | Upright blade, repeated strikes, reactive dummy | Preserve knife slash/throw and existing ragdoll combat |
| 38.4–42.4 s | Clearly labeled interactive environmental control | Three encounter pedestals with a release/fight prompt |
| 77.6–85.6 s | Contextual controls, grab/throw, visible hit reactions | Preserve existing grab/throw; add contextual encounter hints |
| 86–87 s; 144–155.2 s | Category tabs, weapon thumbnails, explicit equip state | Searchable arsenal sharing the existing hotbar and Q wheel; no new purchases or weapon locks |
| 87.6–112.8 s | Pistol magazine count and reload | Server magazine/reload state, T/controller/tap reload and automatic empty reload |
| 118–128 s | Bow with draw percentage | Server-timed draw and swept ballistic arrows, client charge indicator |
| 98–110 s; 131.6–140.4 s | Huge humanoid cyclops in a cage, broad shoulders, long arms, one eye | Original articulated Cyclops with eye weak point, interruptible windup, ground slam, death ragdoll and respawn |

Minotaur and Talos are original additions inferred from the user's request for mythological creatures, not creatures identified in this recording. Attack timings, weak-point rules, XP and sound choices are authored choices; 0.4-second stills cannot establish precise fast-motion timing or sound.

## Current functionality

- Myth Yard: three articulated actors, release prompts, chase/return, attack warnings, vulnerability/recovery, death, session XP, respawn.
- Cyclops: eye multiplier/stun and jumpable area slam. Minotaur: locked charge with a lane warning. Talos: ankle seal multiplier/stun and delayed targeted impact.
- Existing weapon rays/punches/blasts can damage monsters. Direct gun, melee, punch and bow hits credit the attacking player; area damage currently lacks attacker attribution, so unassisted blast-only kills do not award XP.
- Arsenal: J or backpack button; Q wheel remains. Reload: T, D-pad down, or magazine button. Bow: hold attack, release to fire. Challenge: hold Y at the pedestal.
- XP is session-only. This checkpoint introduces no DataStore writes, purchases or published assets.

## Evidence and remaining checks

Rojo build passed and 61 source Luau files compiled before the last small fixes; final compilation/build is recorded in the delivery. Studio place 138972632657672, one desktop client.

Observed integration passes: body versus eye damage (10 versus 25 and stun), Cyclops windup/strike/recovery with player damage, Minotaur charge movement, Talos ankle damage and targeted windup, death ragdoll with exactly one +100 XP reward. Three actors spawned. Arsenal opened through real keyboard input and rendered its labels, categories and equip buttons.

The first rig assertion expected 16 motors, but the authored tree has 15 (root, waist, neck and six per side); the assertion was corrected. The reload integration case did not refill to 15 while concurrent encounters were still running; its setup now moves the character away before testing, but that correction has not been rerun. Respawn completion was not captured before stopping Play.

The Studio capture returned a black 3D scene and empty 3D thumbnails despite replicated geometry. A native-window inspection could not obtain access. Consequently, model appearance, motion quality, arrows through real input, full gun/reload interaction, phone/touch, multiplayer and performance budgets remain unverified. This is a source checkpoint, not a claim that the whole reference implementation is polished or release-ready.

Regression harness: `tools/test-myth.server.luau`, executed only as a temporary normal server Script in Studio Play. It is outside the shipped Rojo source tree. Play was stopped; temporary test instances vanish with that session. A pre-change Studio source copy was retained in `ServerStorage.CodexBeforeMyth_20261116` for recovery and is not part of the Rojo build.
