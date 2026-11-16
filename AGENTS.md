# Ragdoll Mayhem project instructions

This is the Roblox Ragdoll Mayhem project, maintained as Luau files with Rojo.

## Required project skills

Use the project skills for every development, review, debugging, animation, art, or testing task in this repository. The shared skill directory is `.claude/skills/`; Codex must read these files directly even when they are not listed in its current skill catalog. Claude discovers the same directory natively.

Start each development task by reading `roblox-dev/SKILL.md` once. Then select all relevant specialists below and read their `SKILL.md` plus only the references needed for the task. Do not load all ten full packages on every turn.

| Task | Required skill directories under `.claude/skills/` |
| --- | --- |
| General Roblox development, Rojo, models, project conventions | `roblox-dev` |
| Ragdolls, constraints, impulses, network ownership | `roblox-physics` |
| Animator playback, priorities, markers, effect cleanup | `roblox-animation-vfx` |
| Authored R15/R6 attacks, locomotion, Blender preview/export | `roblox-animation` |
| Animation layering, modern joints, IK, rig inspection | `scenario-roblox-animation` |
| NPC behavior, hitboxes, combos, projectiles, knockback | `scenario-roblox-gameplay` |
| Hit effects, weapon slashes, explosions, particle textures | `roblox-vfx-animation` |
| Mesh/beam combat effects, pooling, camera impact | `roblox-mesh-vfx` |
| FPS, physics cost, memory, rendering, network performance | `roblox-performance` |
| Playtesting, regression, death/respawn, first-player experience | `roblox-playtesting` |

`scenario-roblox-expert` and `roblox-skills-setup` are supporting dependencies: read them when a selected specialist requires them or when setting up its tools.

For gameplay changes, also use `roblox-playtesting`. For changes to effects or ragdolls, also use `roblox-performance` to choose relevant checks; do not claim a performance improvement without measurements.

## Apply skills to this project

- User instructions and this project's requirements take precedence over third-party house defaults. Higher-priority platform and safety instructions always apply.
- Preserve the existing game architecture, camera, weapon selection and Rojo structure unless the task requires a change. Reuse existing modules before importing a second runtime for the same feature.
- Upstream examples, fixed polygon targets, visual styles, extra approval rituals, and operating-system paths are defaults, not project requirements. This project runs on Windows; adapt platform-specific commands.
- Use the available Roblox Studio MCP schemas. Scenario/PhotoCraft/Blender-specific tools are optional dependencies, not evidence that those tools are installed here. Never claim an unavailable check passed.
- Installed packages are development instructions and helper resources. Do not copy their demo games into `src/`, run downloaded setup/upload scripts, publish assets, or activate extra services merely because an upstream skill suggests it.
- Keep visual feedback on the client and validate gameplay outcomes on the server. Preserve cosmetic sway separately from the hit ray.
- Compile changed Luau, build with Rojo when relevant, and run focused Studio checks. Report actual results and any material limitations.

## Installation provenance

Exact source revisions and file hashes are recorded in `tools/roblox-skills.lock.json`. Keep upstream licenses and notices with each installed package. Update skill packages deliberately rather than fetching their latest versions during ordinary game work.
