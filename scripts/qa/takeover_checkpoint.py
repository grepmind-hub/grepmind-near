"""Create a private checkpoint of worktree changes without credential files."""
import pathlib
import subprocess
import zipfile

root = pathlib.Path(__file__).resolve().parents[2]
destination = root / "dist" / "takeover-checkpoint-20261121.zip"
destination.parent.mkdir(parents=True, exist_ok=True)
if destination.exists():
    raise SystemExit("checkpoint already exists; refusing to overwrite")

def git(*args):
    return subprocess.check_output(["git", "-c", "core.safecrlf=false", *args], cwd=root)

patch = git("diff", "--binary", "HEAD", "--")
untracked = git("ls-files", "--others", "--exclude-standard", "-z").decode().split("\0")
with zipfile.ZipFile(destination, "x", compression=zipfile.ZIP_DEFLATED) as archive:
    archive.writestr("tracked-changes.patch", patch)
    for name in untracked:
        if not name or name.startswith("dist/"):
            continue
        path = root / name
        lower = name.lower()
        if ("secret" in lower or "private_key" in lower or lower.endswith((".jks", ".keystore", ".pem", ".p12")) or
                (path.name.startswith(".env") and path.name != ".env.example") or
                (lower.endswith(".json") and not lower.endswith("google-services.json") and "/evidence" not in lower)):
            continue
        if path.is_file():
            archive.write(path, "untracked/" + name)
print("Created checkpoint:", destination)
