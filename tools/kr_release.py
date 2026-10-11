"""RustDesk KR release operations using an ignored local profile."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import zipfile


ROOT = Path(__file__).resolve().parents[1]
ABIS = {"arm64-v8a": 2000, "x86_64": 4000}


def command(argv, env=None):
    result = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", env=env)
    if result.returncode:
        raise RuntimeError(f"{Path(argv[0]).name} exited {result.returncode}")
    return result.stdout


def gh(argv):
    return command(["gh", *argv])


def gh_json(argv):
    return json.loads(gh(argv), parse_int=str)


def emit(data):
    print(json.dumps(data, ensure_ascii=True), flush=True)


def local_path(value):
    path = (ROOT / value).resolve()
    if not path.is_relative_to(ROOT / ".local"):
        raise ValueError("Release files must be inside the workspace .local directory")
    return path


class Release:
    def __init__(self, profile):
        self.path = local_path(profile)
        ignored = subprocess.run(["git", "check-ignore", "-q", str(self.path)], cwd=ROOT)
        if ignored.returncode:
            raise ValueError("Release profile must be explicitly Git-ignored")
        self.profile = json.loads(self.path.read_text(encoding="utf-8"), parse_int=str)
        p = self.profile
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", p["repository"]):
            raise ValueError("Invalid repository")
        if not re.fullmatch(r"[0-9a-f]{40}", p["commit"]):
            raise ValueError("An exact source commit is required")
        if not re.fullmatch(r"v\d+\.\d+\.\d+-kr\.\d+", p["tag"]):
            raise ValueError("Invalid KR release tag")
        self.version = p["tag"][1:]
        self.directory = local_path(p.get("release_dir", ".local/releases/" + p["tag"]))
        self.repository = p["repository"]

    def save(self):
        self.path.write_text(json.dumps(self.profile, ensure_ascii=True, indent=2),
                             encoding="utf-8", newline="\n")

    def status(self):
        p = self.profile
        if not p.get("run_id"):
            runs = gh_json(["run", "list", "--repo", self.repository,
                            "--workflow", p["workflow"], "--limit", "5",
                            "--json", "databaseId,headSha"])
            matches = [r for r in runs if r["headSha"] == p["commit"]]
            if not matches:
                raise RuntimeError("No workflow run matches the release source")
            p["run_id"] = matches[0]["databaseId"]
            self.save()
        if not re.fullmatch(r"\d+", p["run_id"]):
            raise ValueError("Invalid run ID")
        run = gh_json(["run", "view", p["run_id"], "--repo", self.repository,
                      "--json", "status,conclusion,headSha,jobs,url,workflowName"])
        if run["headSha"] != p["commit"]:
            raise RuntimeError("CI source differs from the release profile")
        workflow = command(["git", "show", p["commit"] + ":.github/workflows/" + p["workflow"]])
        match = re.search(r"^name:\s*(.+)$", workflow, re.MULTILINE)
        if not match or run["workflowName"] != match[1].strip().strip("'\""):
            raise RuntimeError("CI workflow differs from the release profile")
        return {"run_id": p["run_id"], "commit": run["headSha"], "url": run["url"],
                "status": run["status"], "conclusion": run["conclusion"],
                "jobs": [{"name": j["name"], "status": j["status"],
                          "conclusion": j["conclusion"],
                          "active_step": next((s["name"] for s in j["steps"]
                                               if s["status"] == "in_progress"), None)}
                         for j in run["jobs"]]}

    def successful(self):
        run = self.status()
        if run["status"] != "completed" or run["conclusion"] != "success":
            raise RuntimeError("Source build is not successfully completed")
        if not run["jobs"] or any(j["conclusion"] != "success" for j in run["jobs"]):
            raise RuntimeError("Every expected CI job must succeed")
        return run

    def watch(self):
        while True:
            run = self.status()
            emit(run)
            if run["status"] == "completed":
                if run["conclusion"] != "success":
                    raise RuntimeError("CI failed; inspect the failed step")
                return
            time.sleep(300)

    def private_values(self):
        p = self.profile
        values = [str(ROOT), str(Path.home()), *p.get("private_literals", [])]
        values += [p.get(k, "") for k in ("store_password", "key_password", "signing_key_path")]
        result = set()
        for value in filter(None, values):
            for variant in (value, value.replace("\\", "/"), value.replace("/", "\\")):
                result.add(variant.encode("utf-8"))
                result.add(variant.encode("utf-16le"))
        return result

    def check_private(self, data):
        if any(value in data for value in self.private_values()):
            raise RuntimeError("Private local data found in a release file")

    def build_tools(self):
        folder = Path(self.profile["android_build_tools"])
        if not folder.is_absolute():
            folder = ROOT / folder
        aapt = folder / ("aapt.exe" if os.name == "nt" else "aapt")
        signer = folder / ("apksigner.bat" if os.name == "nt" else "apksigner")
        if not aapt.is_file() or not signer.is_file():
            raise RuntimeError("Configured Android build tools are unavailable")
        env = os.environ.copy()
        if self.profile.get("java_home"):
            env["JAVA_HOME"] = self.profile["java_home"]
        return aapt, signer, env

    def verify_apk(self, file, abi):
        p = self.profile
        aapt, signer, env = self.build_tools()
        metadata = command([str(aapt), "dump", "badging", str(file)], env)
        package = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", metadata)
        expected_code = str(ABIS[abi] + int(p["build_number"]))
        if not package or package.groups() != ("com.carriez.flutter_hbb.kr", expected_code, self.version):
            raise RuntimeError("APK package, version or build number differs")
        if "application-label:'RustDesk KR'" not in metadata:
            raise RuntimeError("Unexpected launcher label")
        args = [str(signer), "verify", "--verbose", "--print-certs", str(file)]
        if os.name == "nt":
            args = ["cmd.exe", "/c", *args]
        signed = command(args, env)
        certificate = Path(p["certificate_path"])
        if not certificate.is_absolute():
            certificate = ROOT / certificate
        expected_signer = hashlib.sha256(certificate.read_bytes()).hexdigest()
        match = re.search(r"Signer #1 certificate SHA-256 digest: ([a-fA-F0-9]+)", signed)
        if not match or match[1].lower() != expected_signer:
            raise RuntimeError("APK signing certificate differs")
        private = self.private_values()
        overlap = max((len(value) for value in private), default=1) - 1
        with zipfile.ZipFile(file) as archive:
            if archive.testzip() is not None:
                raise RuntimeError("APK ZIP integrity failed")
            libs = [n for n in archive.namelist() if n.endswith("/librustdesk.so")]
            if libs != ["lib/" + abi + "/librustdesk.so"]:
                raise RuntimeError("APK native ABI differs")
            for entry in archive.infolist():
                name = entry.filename.replace("\\", "/")
                if ".local" in name.split("/") or name.endswith((".jks", ".keystore", "key.properties")):
                    raise RuntimeError("Private file embedded in APK")
                if entry.is_dir():
                    continue
                with archive.open(entry) as stream:
                    tail = b""
                    while block := stream.read(1024 * 1024):
                        data = tail + block
                        if any(value in data for value in private):
                            raise RuntimeError("Private local data embedded in APK")
                        tail = data[-overlap:] if overlap else b""
        return {"filename": "rustdesk-kr-" + self.version + "-" + abi + ".apk",
                "abi": abi, "sha256": hashlib.sha256(file.read_bytes()).hexdigest(),
                "version_name": self.version, "version_code": expected_code,
                "signer_sha256": expected_signer, "signature_verified": True,
                "private_data_matches": 0}

    def verify(self):
        self.successful()
        p = self.profile
        if not 0 < int(p["build_number"]) < 1000:
            raise ValueError("Invalid split-ABI build number")
        artifacts = gh_json(["api", f"repos/{self.repository}/actions/runs/{p['run_id']}/artifacts?per_page=100"])
        selected = {}
        for abi in ABIS:
            aliases = ("aarch64", "arm64", "arm64-v8a") if abi == "arm64-v8a" else ("x86_64",)
            names = {"rustdesk-kr-" + self.version + "-" + a + ".apk" for a in aliases}
            matches = [a for a in artifacts["artifacts"] if a["name"] in names and not a["expired"]]
            if len(matches) != 1:
                raise RuntimeError("Expected exactly one current artifact per ABI")
            selected[abi] = matches[0]["name"]
        self.directory.mkdir(parents=True, exist_ok=True)
        verified = []
        with tempfile.TemporaryDirectory(prefix="kr-release-") as temp:
            work = Path(temp).resolve()
            if work.parent != Path(tempfile.gettempdir()).resolve():
                raise RuntimeError("Temporary directory is outside the OS temporary root")
            for abi, name in selected.items():
                folder = work / abi
                folder.mkdir()
                gh(["run", "download", p["run_id"], "--repo", self.repository,
                    "--name", name, "--dir", str(folder)])
                files = list(folder.glob("*.apk"))
                if len(files) != 1:
                    raise RuntimeError("Artifact must contain exactly one APK")
                item = self.verify_apk(files[0], abi)
                shutil.copy2(files[0], self.directory / item["filename"])
                verified.append(item)
        p["artifact_names"] = selected
        p["verified_apks"] = verified
        p["verified_commit"] = p["commit"]
        p["verified_run_id"] = p["run_id"]
        self.save()
        return {"status": "verified", "commit": p["commit"], "run_id": p["run_id"],
                "verified_apks": verified}

    def release(self, publish):
        self.successful()
        p = self.profile
        if p.get("verified_commit") != p["commit"] or p.get("verified_run_id") != p["run_id"]:
            raise RuntimeError("APK verification is not bound to this source run")
        apks = p.get("verified_apks", [])
        if len(apks) != 2 or {a["abi"] for a in apks} != set(ABIS):
            raise RuntimeError("Complete verified APK set required")
        for item in apks:
            file = self.directory / item["filename"]
            expected_name = "rustdesk-kr-" + self.version + "-" + item["abi"] + ".apk"
            expected_code = str(ABIS[item["abi"]] + int(p["build_number"]))
            if (item["filename"] != expected_name or item["version_name"] != self.version
                    or item["version_code"] != expected_code or not item["signature_verified"]
                    or int(item["private_data_matches"]) != 0):
                raise RuntimeError("Invalid verified APK record")
            if hashlib.sha256(file.read_bytes()).hexdigest() != item["sha256"]:
                raise RuntimeError("APK changed after verification")
        notes = local_path(p["release_notes"])
        text = notes.read_text(encoding="utf-8")
        if self.version not in text:
            raise RuntimeError("Release notes do not describe this version")
        self.check_private(text.encode("utf-8"))
        checksums = self.directory / "SHA256SUMS.txt"
        checksum_text = "".join(a["sha256"] + "  " + a["filename"] + "\n" for a in apks)
        if not checksums.exists() or checksums.read_text(encoding="utf-8") != checksum_text:
            checksums.write_text(checksum_text, encoding="utf-8", newline="\n")
        expected = {a["filename"]: a["sha256"] for a in apks}
        expected[checksums.name] = hashlib.sha256(checksums.read_bytes()).hexdigest()
        plan = {"status": "ready", "publish": publish, "tag": p["tag"], "commit": p["commit"],
                "assets": expected, "ci_url": self.status_url()}
        if not publish:
            return plan
        tags = gh_json(["api", "repos/" + self.repository + "/releases?per_page=100"])
        existing = next((r for r in tags if r["tag_name"] == p["tag"]), None)
        if existing is None:
            tag = subprocess.run(["git", "rev-parse", "--verify", "refs/tags/" + p["tag"]],
                                 cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
            if tag.returncode == 0:
                if tag.stdout.strip() != p["commit"]:
                    raise RuntimeError("Existing tag points to another source")
            else:
                command(["git", "tag", p["tag"], p["commit"]])
            remote = command(["git", "remote", "get-url", "origin"]).strip()
            if remote not in ("https://github.com/" + self.repository + ".git",
                              "https://github.com/" + self.repository,
                              "git@github.com:" + self.repository + ".git"):
                raise RuntimeError("Git origin differs from the release repository")
            command(["git", "push", "origin", "refs/tags/" + p["tag"]])
            gh(["release", "create", p["tag"], "--repo", self.repository, "--verify-tag",
                "--prerelease", "--title", "RustDesk KR " + self.version, "--notes-file", str(notes),
                *[str(self.directory / a["filename"]) for a in apks], str(checksums)])
        released = gh_json(["api", "repos/" + self.repository + "/releases/tags/" + p["tag"]])
        if released["draft"] or not released["prerelease"]:
            raise RuntimeError("Unexpected published release state")
        tag_ref = gh_json(["api", "repos/" + self.repository + "/git/ref/tags/" + p["tag"]])
        if tag_ref["object"]["type"] != "commit" or tag_ref["object"]["sha"] != p["commit"]:
            raise RuntimeError("Published tag differs from the tested source")
        actual = {a["name"]: a.get("digest") for a in released["assets"]}
        if actual != {name: "sha256:" + digest for name, digest in expected.items()}:
            raise RuntimeError("Published assets differ; no automatic overwrite performed")
        normalize = lambda s: s.replace("\r\r\n", "\n").replace("\r\n", "\n").rstrip()
        if normalize(released["body"]) != normalize(text):
            raise RuntimeError("Published release notes differ")
        p["release_url"] = released["html_url"]
        p["release_assets"] = [{"name": a["name"], "url": a["browser_download_url"],
                                "sha256": expected[a["name"]]} for a in released["assets"]]
        p["ci_result"] = "success"
        self.save()
        return {**plan, "status": "published", "url": p["release_url"]}

    def status_url(self):
        return f"https://github.com/{self.repository}/actions/runs/{self.profile['run_id']}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("status", "watch", "verify", "release"))
    parser.add_argument("--profile", default=".local/release-profile.json")
    parser.add_argument("--publish", choices=("true", "false"), default="false",
                        help="release action only; false prepares a reviewable plan")
    args = parser.parse_args()
    release = Release(args.profile)
    if args.action == "watch":
        release.watch()
    elif args.action == "status":
        emit(release.status())
    elif args.action == "verify":
        emit(release.verify())
    else:
        emit(release.release(args.publish == "true"))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, zipfile.BadZipFile) as error:
        emit({"status": "error", "error": str(error)})
        raise SystemExit(1)
