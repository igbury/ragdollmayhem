# Project skill sources

Preserve the license and notice files included with every installed skill. Source revisions and hashes are recorded in `roblox-skills.lock.json`.

- `roblox-animation` and `roblox-skills-setup` come from [SyphoDev's free Roblox skills](https://github.com/SyphoDev-yt/roblox-ai-skills). Source: [SyphoDev on YouTube](https://www.youtube.com/@SyphoDev). Their included free license permits personal and commercial project use and free sharing with that attribution; it does not permit selling the skills or including them in a paid bundle.
- `roblox-mesh-vfx` comes from [Willikk/Roblox](https://github.com/Willikk/Roblox). Its upstream README declares MIT licensing for personal and commercial games. The declaration is preserved as `UPSTREAM-README.md` in that package.
- The remaining upstream packages include their MIT licenses and third-party notices where supplied.
- `tools/vendor/yaml` is the pure-Python PyYAML implementation used only by the skill metadata validator. Its MIT license is in `tools/vendor/PyYAML-LICENSE`.
- The optional `VFX-Pack-KanzeroGaming.rbxm` asset is not bundled in this installation because binary download was unavailable. The instructional skill and its scripts remain usable with the project's existing assets and procedural fallbacks. Its exact source and hash are in the lock file.
