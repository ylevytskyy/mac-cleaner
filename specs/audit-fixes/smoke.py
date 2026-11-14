"""Регресійні сценарії для знахідок аудиту 2026-11-11 (H1-H5).

Кожен сценарій запускає справжній mac-cleaner.sh у власній одноразовій
теці HOME зі штучним PATH (лише заглушки + /usr/bin:/bin) і з --only на
категоріях, що чіпають тільки $HOME. Нічого поза тимчасовою текою не
видаляється.

Запуск: python3 -I specs/audit-fixes/smoke.py [назва_сценарію ...]
"""

import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile


SCRIPT = Path(__file__).resolve().parents[2] / "mac-cleaner.sh"
NO_USER = "aa-smoke-no-such-user"


def put(path, size=8192):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"x" * size)
    return path


def lock(directory):
    """Каталог, з якого rm -rf не зможе видалити вміст (mode 555)."""
    put(directory / "held")
    directory.chmod(0o555)
    return directory


def unlock_all(root):
    for dirpath, dirnames, _ in os.walk(root):
        for name in dirnames:
            p = Path(dirpath) / name
            try:
                p.chmod(p.stat().st_mode | stat.S_IRWXU)
            except OSError:
                pass


def stub(bin_dir, name, body):
    p = bin_dir / name
    p.write_text("#!/bin/sh\n" + body + "\n")
    p.chmod(0o755)


class Sandbox:
    def __init__(self, root):
        self.root = root
        self.home = root / "home"
        self.home.mkdir()
        self.bin = root / "bin"
        self.bin.mkdir()
        (root / "tmp").mkdir()
        # pgrep завжди "нічого не знайшов": живі застосунки користувача не впливають.
        stub(self.bin, "pgrep", "exit 1")
        self.env = {
            "HOME": str(self.home),
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "USER": NO_USER,
            "LOGNAME": NO_USER,
            "TMPDIR": str(root / "tmp") + "/",
            "LANG": "en_US.UTF-8",
        }

    @property
    def log(self):
        p = self.home / ".mac-cleaner.log"
        return p.read_text() if p.exists() else ""

    def run(self, *args, input=""):
        r = subprocess.run(
            ["/bin/zsh", str(SCRIPT), *args],
            env=self.env, input=input, text=True, capture_output=True, timeout=60,
        )
        return r.returncode, r.stdout + r.stderr


def expect(cond, msg, out=""):
    if not cond:
        raise AssertionError(msg + ("\n--- output ---\n" + out[-3000:] if out else ""))


def log_has(log, event, *parts):
    return any(
        line.split()[1:2] == [event] and all(p in line for p in parts)
        for line in log.splitlines() if len(line.split()) > 1
    )


# ── H1: одна невдала команда не обриває весь прогін ─────────────────────

def errexit_inline(sb):
    lock(sb.home / ".npm/_logs/locked")
    put(sb.home / "Library/Caches/node-gyp/x")
    nxt = put(sb.home / ".cache/pre-commit/repo/x")
    rc, out = sb.run("--only", "node_extras,python_extras", "--yes")
    log = sb.log
    expect(rc == 0, f"прогін завершився з rc={rc}, очікувався 0", out)
    expect(log_has(log, "END"), "немає рядка END у лозі", log)
    expect(log_has(log, "ERROR", "category=node_extras"), "немає ERROR для node_extras", log)
    expect(not log_has(log, "CLEAN", "category=node_extras"), "невдала node_extras залогована як CLEAN", log)
    expect(not nxt.exists(), "наступна категорія (python_extras) не відпрацювала", out)


def errexit_browser(sb):
    lock(sb.home / "Library/Application Support/Windsurf/Cache/locked")
    nxt = put(sb.home / "Library/Application Support/discord/Cache/data")
    rc, out = sb.run("--only", "browsers", "--yes")
    log = sb.log
    expect(rc == 0, f"прогін завершився з rc={rc}, очікувався 0", out)
    expect(log_has(log, "END"), "немає рядка END у лозі", log)
    expect(log_has(log, "ERROR", "browser=windsurf"), "немає ERROR для windsurf", log)
    expect(not log_has(log, "CLEAN", "browser=windsurf"), "невдалий windsurf залогований як CLEAN", log)
    expect(not nxt.exists(), "наступний браузер (discord) не відпрацював", out)


# ── H2: невдале/часткове видалення не логується як CLEAN ────────────────

def false_clean_paths(sb):
    lock(sb.home / "Library/Logs/locked")
    rc, out = sb.run("--only", "user_logs", "--yes")
    log = sb.log
    expect(rc == 0, f"rc={rc}", out)
    expect(log_has(log, "ERROR", "user_logs"), "немає ERROR для user_logs", log)
    expect(not log_has(log, "CLEAN", "category=user_logs"), "невдалий user_logs залогований як CLEAN", log)


def false_clean_brew(sb):
    put(sb.home / "brewcache/f")
    stub(sb.bin, "brew", (
        'case "$1" in\n'
        '  --cache) echo "$HOME/brewcache" ;;\n'
        '  cleanup) echo "Error: stub pinned formula" >&2; exit 1 ;;\n'
        '  *) exit 0 ;;\n'
        'esac'))
    rc, out = sb.run("--only", "brew", "--yes")
    log = sb.log
    expect(rc == 0, f"rc={rc}", out)
    expect(log_has(log, "ERROR", "category=Homebrew"), "brew cleanup упав, але ERROR немає", log)
    expect(not log_has(log, "CLEAN", "category=Homebrew"), "невдалий brew залогований як CLEAN", log)


def false_clean_bazel(sb):
    sys_path = Path(f"/private/var/tmp/_bazel_{NO_USER}")
    expect(not sys_path.exists(), f"{sys_path} існує — сценарій небезпечний, зупинка")
    stub(sb.bin, "bazel", "exit 0")
    lock(sb.home / "Library/Caches/bazel/locked")
    rc, out = sb.run("--only", "bazel", "--yes")
    log = sb.log
    expect(rc == 0, f"rc={rc}", out)
    expect(log_has(log, "ERROR", "bazel"), "немає ERROR для bazel", log)
    expect(not log_has(log, "CLEAN", "category=bazel"), "bazel після ERROR ще й залогований як CLEAN", log)


# ── H3: сирітський pnpm v3 store ─────────────────────────────────────────

def pnpm_v3_dryrun(sb):
    blob = put(sb.home / "Library/pnpm/store/v3/files/blob", 200 * 1024)
    rc, out = sb.run("--only", "pnpm", "--dry-run", "--yes")
    log = sb.log
    expect(rc == 0, f"rc={rc}", out)
    expect(blob.exists(), "--dry-run видалив v3 store", out)
    bad = [l for l in log.splitlines()
           if " CLEAN " in l and "remove_v3_orphan" in l and "freed_bytes=0" not in l]
    expect(not bad, "--dry-run залогував звільнені байти для v3: " + "; ".join(bad), log)


def pnpm_v3_failed(sb):
    lock(sb.home / "Library/pnpm/store/v3/locked")
    rc, out = sb.run("--only", "pnpm", "--yes")
    log = sb.log
    expect(rc == 0, f"rc={rc}", out)
    expect(not log_has(log, "CLEAN", "remove_v3_orphan"), "невдале видалення v3 залоговане як CLEAN", log)
    expect(log_has(log, "ERROR", "pnpm"), "немає ERROR для невдалого видалення v3", log)


# ── H4: glob у дочірньому zsh ─────────────────────────────────────────────

def trash_dotfile_only(sb):
    put(sb.home / ".Trash/.DS_Store")
    rc, out = sb.run("--only", "trash", "--yes")
    log = sb.log
    expect(rc == 0, f"rc={rc}", out)
    expect(not log_has(log, "ERROR"), "кошик лише з dotfile дав ERROR", log)
    expect(not any((sb.home / ".Trash").iterdir()), "dotfile лишився в кошику", out)


def trash_hidden_files(sb):
    put(sb.home / ".Trash/visible.txt")
    put(sb.home / ".Trash/.hidden-trashed", 64 * 1024)
    rc, out = sb.run("--only", "trash", "--yes")
    log = sb.log
    expect(rc == 0, f"rc={rc}", out)
    expect(not log_has(log, "ERROR"), "кошик дав ERROR", log)
    left = sorted(p.name for p in (sb.home / ".Trash").iterdir())
    expect(not left, f"у кошику лишилось: {left}", out)


def glob_no_match(sb):
    # Обидва каталоги існують, але в XCPGDevices нічого немає: glob без збігів
    # не має перетворюватися на ERROR.
    dev = put(sb.home / "Library/Developer/XCTestDevices/dev1/data")
    (sb.home / "Library/Developer/XCPGDevices").mkdir(parents=True)
    rc, out = sb.run("--only", "xctest", "--yes")
    log = sb.log
    expect(rc == 0, f"rc={rc}", out)
    expect(not log_has(log, "ERROR"), "glob без збігів дав ERROR", log)
    expect(not dev.exists(), "XCTestDevices не очищено", out)


# ── H5: app_caches не чіпає кеші, якими володіють інші категорії ─────────

OWNED = ("CocoaPods", "Mozilla.sccache", "bazel", "go-build")


def app_caches_owned(sb):
    caches = sb.home / "Library/Caches"
    for name in OWNED + ("com.example.app",):
        put(caches / name / "data")
    rc, out = sb.run("--only", "app_caches", "--dry-run", "--yes")
    expect(rc == 0, f"rc={rc}", out)
    planned = [l for l in out.splitlines() if "[dry-run]" in l]
    expect(any("com.example.app" in l for l in planned), "звичайний кеш не потрапив у план", out)
    hit = [n for n in OWNED if any(f"/Library/Caches/{n}" in l for l in planned)]
    expect(not hit, f"app_caches видаляє чужі кеші: {hit}", out)


# ── Часткове видалення: ERROR, але звільнені байти враховано ─────────────

def end_freed(log):
    for line in log.splitlines():
        if line.split()[1:2] == ["END"]:
            return int(line.split("freed_total=")[1].split()[0])
    return None


def expect_partial(sb, rc, out, cat):
    log = sb.log
    expect(rc == 0, f"rc={rc}", out)
    errs = [l for l in log.splitlines() if " ERROR " in l and f"category={cat}" in l]
    expect(len(errs) == 1, f"очікувався рівно один ERROR для {cat}, є {len(errs)}", log)
    expect("partial=true" in errs[0], "ERROR без partial=true", log)
    freed = int(errs[0].split("freed_bytes=")[1].split()[0]) if "freed_bytes=" in errs[0] else 0
    expect(freed >= 64 * 1024, f"freed_bytes={freed}, очікувалось >= 64K", log)
    expect(not log_has(log, "CLEAN", f"category={cat}"), "часткове видалення залоговане як CLEAN", log)
    expect((end_freed(log) or 0) >= freed, "freed_total у END не містить часткові байти", log)


def partial_app_caches(sb):
    caches = sb.home / "Library/Caches"
    lock(caches / "com.example.locked/sub")
    put(caches / "com.example.big/data", 256 * 1024)
    rc, out = sb.run("--only", "app_caches", "--yes")
    expect_partial(sb, rc, out, "app_caches")


def partial_paths(sb):
    lock(sb.home / "Library/Logs/locked")
    put(sb.home / "Library/Logs/big.log", 256 * 1024)
    rc, out = sb.run("--only", "user_logs", "--yes")
    expect_partial(sb, rc, out, "user_logs")


def partial_run_category(sb):
    lock(sb.home / "Library/Developer/Xcode/DerivedData/locked")
    put(sb.home / "Library/Developer/Xcode/DerivedData/Proj-abc/data", 256 * 1024)
    rc, out = sb.run("--only", "deriveddata", "--yes")
    expect_partial(sb, rc, out, "Xcode DerivedData")


SCENARIOS = {f.__name__: f for f in (
    errexit_inline, errexit_browser,
    false_clean_paths, false_clean_brew, false_clean_bazel,
    pnpm_v3_dryrun, pnpm_v3_failed,
    trash_dotfile_only, trash_hidden_files, glob_no_match,
    app_caches_owned,
    partial_app_caches, partial_paths, partial_run_category,
)}


def main(names):
    failed = 0
    for name in names or SCENARIOS:
        root = Path(tempfile.mkdtemp(prefix="mac-cleaner-audit-"))
        try:
            SCENARIOS[name](Sandbox(root))
            print(f"PASS {name}")
        except AssertionError as e:
            failed += 1
            print(f"FAIL {name}: {e}")
        finally:
            unlock_all(root)
            shutil.rmtree(root, ignore_errors=True)
    print(f"\n{len(names or SCENARIOS) - failed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
