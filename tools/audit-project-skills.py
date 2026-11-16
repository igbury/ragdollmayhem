"""Validate the installed project skills and record reproducible source provenance."""
import argparse
import ast
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
PROJECT = TOOLS.parent
ROOT = PROJECT / ".claude" / "skills"
LOCK = TOOLS / "roblox-skills.lock.json"
sys.path.insert(0, str(TOOLS / "vendor"))
from quick_validate_skill import validate_skill


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def collect_sources():
    sources = json.loads((TOOLS / "roblox-skills-sources.json").read_text(encoding="utf-8"))
    original = json.loads((TOOLS / "roblox-skills-reviewed.json").read_text(encoding="utf-8"))
    records = list(sources["files"])
    for item in original["files"]:
        records.append({
            "path": item["path"], "repo": original["repository"], "revision": original["revision"],
            "source": "LICENSE" if item["path"].endswith("/LICENSE") else "skills/" + item["path"],
            "sha": item["blob"], "size": len(item["content"].encode("utf-8")),
        })
    records.append({
        "path": "roblox-mesh-vfx/UPSTREAM-README.md", "repo": "Willikk/Roblox",
        "revision": "c77902e8f59cc0ca1f3130906ae51c92d9de310e", "source": "README.md",
        "sha": "f82d6c585114c09647400950478b59d636b9101c", "size": None,
    })
    return sources, records


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write-lock", action="store_true")
    parser.add_argument("--syntax", action="store_true")
    args = parser.parse_args()
    sources, records = collect_sources()
    names = sources["requested_skills"] + sources["dependencies"]
    errors = []
    for name in names:
        ok, message = validate_skill(ROOT / name)
        if not ok:
            errors.append(f"{name}: {message}")
            continue
        content = (ROOT / name / "SKILL.md").read_text(encoding="utf-8")
        import yaml
        header = yaml.safe_load(content.split("---", 2)[1])
        if header["name"] != name:
            errors.append(f"Frontmatter name differs from directory: {name}")
        for target in re.findall(r"\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)", content):
            if re.match(r"(?:[a-z]+:|/|#)", target, re.I):
                continue
            relative = target.split("#", 1)[0]
            if relative and not (ROOT / name / relative).exists():
                errors.append(f"Missing local skill reference: {name}/{relative}")
    installed = []
    for record in records:
        file = ROOT / record["path"]
        if not file.is_file():
            errors.append(f"Missing installed resource: {record['path']}")
            continue
        data = file.read_bytes()
        installed.append({**record, "installed_sha256": digest(data), "installed_bytes": len(data)})
    if args.syntax:
        python_count = 0
        for path in ROOT.rglob("*.py"):
            try:
                ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(path))
                python_count += 1
            except SyntaxError as error:
                errors.append(f"Python syntax: {path.relative_to(ROOT)}: {error}")
        js_count = 0
        node = shutil.which("node")
        if node:
            for path in sorted([*ROOT.rglob("*.mjs"), *ROOT.rglob("*.js")]):
                result = subprocess.run([node, "--check", str(path)], capture_output=True, text=True)
                if result.returncode:
                    errors.append(f"JavaScript syntax: {path.relative_to(ROOT)}: {result.stderr[:300]}")
                else:
                    js_count += 1
        print(f"Helper syntax checked: {python_count} Python, {js_count} JavaScript files.")
    if errors:
        print("\n".join(errors))
        raise SystemExit(1)
    if args.write_lock:
        payload = {
            "format": 1, "skill_root": ".claude/skills", "requested_skills": sources["requested_skills"],
            "dependencies": sources["dependencies"], "files": installed,
            "local_metadata_adaptations": ["roblox-physics", "roblox-animation-vfx", "roblox-vfx-animation"],
            "optional_assets_pending": sources["optional_assets"],
        }
        LOCK.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    else:
        locked = json.loads(LOCK.read_text(encoding="utf-8"))
        for record in locked["files"]:
            if digest((ROOT / record["path"]).read_bytes()) != record["installed_sha256"]:
                raise SystemExit("Installed file differs from lock: " + record["path"])
    print(f"Validated {len(sources['requested_skills'])} requested skills, {len(sources['dependencies'])} supporting skills and {len(installed)} resources.")
    print("Optional binary asset packs pending: " + str(len(sources["optional_assets"])))


if __name__ == "__main__":
    main()
