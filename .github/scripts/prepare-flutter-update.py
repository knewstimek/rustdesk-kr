from pathlib import Path
import hashlib
import json
import os
import subprocess
import tempfile
import zipfile

native_commit = "de5e42bff7f9a67ba4212d24b25eb7ca7323ceee"
tested_commit = "ee592ad9f63f27f6b5d3eabce6e2d641190fb518"
test_run = "37991881551"
abi = os.environ["KR_ABI"]
repository = os.environ["GITHUB_REPOSITORY"]
root = Path.cwd()

def run(args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("Update provenance check failed: " + result.stderr[-1000:])
    return result.stdout

native_paths = ["src", "libs", ".cargo", ".gitmodules", "Cargo.toml",
                "Cargo.lock", "build.rs", "vcpkg.json"]
if run(["git", "diff", "--name-only", native_commit, "HEAD", "--", *native_paths]).strip():
    raise RuntimeError("Native sources changed; use the full-source Android workflow")
if run(["git", "diff", "--name-only", tested_commit, "HEAD", "--",
        "flutter/lib", "flutter/test", "flutter/pubspec.yaml", "flutter/pubspec.lock"]).strip():
    raise RuntimeError("Flutter sources changed after the passing regression tests")
metadata = json.loads(run(["gh", "api", f"repos/{repository}/actions/runs/{test_run}"]), parse_int=str)
if metadata["head_sha"] != tested_commit:
    raise RuntimeError("Regression-test provenance commit mismatch")
jobs = json.loads(run(["gh", "api", f"repos/{repository}/actions/runs/{test_run}/jobs?per_page=100"]), parse_int=str)["jobs"]
if not any(job["name"] == "input-tests" and job["conclusion"] == "success" for job in jobs):
    raise RuntimeError("Passing regression-test result is unavailable")
hashes = {
    "arm64-v8a": "943daf4331ee281eba97adcddbf3afdddbd3a7d2a6c23e0b61781b8b51a6a8c9",
    "x86_64": "ebf63c71b2d105de6505e8ddf74cc914f9650faec5432d77c57524d3410afdb1",
}
if abi not in hashes:
    raise RuntimeError("Unsupported update ABI")
url = f"https://github.com/{repository}/releases/download/v1.5.0-kr.1/rustdesk-kr-1.5.0-kr.1-{abi}.apk"
with tempfile.TemporaryDirectory(prefix="rustdesk-kr-native-") as temporary:
    apk = Path(temporary) / "base.apk"
    run(["curl", "--fail", "--location", "--silent", "--show-error", url, "--output", str(apk)])
    if hashlib.sha256(apk.read_bytes()).hexdigest() != hashes[abi]:
        raise RuntimeError("Pinned native APK checksum mismatch")
    target = root / "flutter/android/app/src/main/jniLibs" / abi
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(apk) as archive:
        for name in ["librustdesk.so", "libc++_shared.so"]:
            (target / name).write_bytes(archive.read(f"lib/{abi}/{name}"))
print("PASS: unchanged native sources and passing Flutter test provenance verified; pinned native libraries restored")
