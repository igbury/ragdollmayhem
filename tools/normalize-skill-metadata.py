"""Adapt upstream frontmatter to the Agent Skills schema without changing skill bodies."""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "vendor"))
import yaml


def main() -> None:
    root = Path(__file__).resolve().parent.parent / ".claude" / "skills"
    allowed = {"name", "description", "license", "allowed-tools", "metadata"}
    changed = []
    for path in sorted(root.glob("*/SKILL.md")):
        original = path.read_text(encoding="utf-8")
        match = re.match(r"\A---\n(.*?)\n---(?:\n|$)", original, re.DOTALL)
        if not match:
            raise ValueError(f"Invalid skill header: {path.parent.name}")
        header = yaml.safe_load(match.group(1))
        extras = {key: header.pop(key) for key in list(header) if key not in allowed}
        if extras:
            metadata = header.setdefault("metadata", {})
            for key, value in extras.items():
                metadata[key] = json.dumps(value, ensure_ascii=False) if isinstance(value, (list, dict)) else str(value)
        long_description = len(header["description"]) > 1024
        if long_description:
            if header["name"] != "roblox-vfx-animation":
                raise ValueError(f"Review the long description in {path}")
            header.setdefault("metadata", {})["upstream_description"] = header["description"]
            header["description"] = (
                "Build Roblox combat VFX and R15/R6 animations through Studio MCP: hits, slashes, "
                "explosions, particles, beams, trails, camera feedback, creature rigs, sprite sheets "
                "and flipbooks. Use for creating, tuning, previewing or debugging Roblox visual effects, "
                "attack or locomotion animations, or VFX textures using the bundled pose compiler, "
                "helper scripts and reference guides."
            )
        if extras or long_description:
            body = original[match.end():]
            new_header = yaml.safe_dump(header, allow_unicode=True, sort_keys=False, width=1000).rstrip()
            path.write_text("---\n" + new_header + "\n---\n" + body, encoding="utf-8", newline="\n")
            changed.append(path.parent.name)
    print("Normalized skill metadata: " + ", ".join(changed))


if __name__ == "__main__":
    main()
