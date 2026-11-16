"""Install pinned, hash-checked upstream files into this project's writable skill directory."""
import argparse
import base64
import hashlib
import json
from pathlib import Path


def git_blob_hash(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("batch", type=Path)
    args = parser.parse_args()
    project = Path(__file__).resolve().parent.parent
    root = (project / ".claude" / "skills").resolve()
    records = json.loads(args.batch.read_text(encoding="utf-8"))
    writes = []
    for record in records:
        relative = Path(record["path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"Unsafe skill path: {relative}")
        destination = (root / relative).resolve()
        if not destination.is_relative_to(root):
            raise ValueError(f"Skill path escaped its root: {relative}")
        data = (base64.b64decode(record["content"], validate=False)
                if record["encoding"] == "base64"
                else record["content"].encode("utf-8"))
        if git_blob_hash(data) != record["sha"]:
            raise ValueError(f"Upstream Git hash mismatch: {relative}")
        if len(data) != record["size"]:
            raise ValueError(f"Upstream size mismatch: {relative}")
        if destination.exists() and destination.read_bytes() != data:
            raise ValueError(f"Preserved a different existing file: {destination}")
        writes.append((destination, data))
    for destination, data in writes:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    print(f"Installed and hash-verified {len(writes)} skill resource files.")


if __name__ == "__main__":
    main()
