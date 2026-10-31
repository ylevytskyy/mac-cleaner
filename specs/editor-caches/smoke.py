"""Перевірка публічного CLI на одноразових файлових даних, без залежностей."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile


SCRIPT = Path(__file__).resolve().parents[2] / "mac-cleaner.sh"
EDITORS = ("Code", "Code - Insiders", "Cursor", "Windsurf")
if len(sys.argv) == 1:
    EDITORS += ("Devin", "Devin - Next")


def put(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"x" * 8192)
    return path


with tempfile.TemporaryDirectory(prefix="mac-cleaner-smoke-") as directory:
    root = Path(directory)
    home = root / "profile"
    bin_dir = root / "bin"
    bin_dir.mkdir()
    pgrep = bin_dir / "pgrep"
    pgrep.write_text('#!/bin/sh\nprintf "%s\\n" "$SMOKE_PROCESS" | /usr/bin/grep -Eq "$2"\n')
    pgrep.chmod(0o755)
    env = dict(os.environ, HOME=str(home), PATH=f"{bin_dir}:/usr/bin:/bin", SMOKE_PROCESS="")
    caches = []
    protected = []
    discord = home / "Library/Application Support/discord"
    caches.append(put(discord / "Cache/data"))
    protected.append(put(discord / "CachedExtensionVSIXs/keep"))
    for editor in EDITORS:
        base = home / "Library/Application Support" / editor
        caches.append(put(base / "CachedExtensionVSIXs/archive.vsix"))
        if editor.startswith("Devin"):
            for leaf in ("Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "CachedData"):
                caches.append(put(base / leaf / "data"))
            protected.append(put(base / "Service Worker/Database/state"))
        protected.append(put(base / "User/settings.json"))
        protected.append(put(base / "User/workspaceStorage/state.db"))
        protected.append(put(base / "extensions/installed/extension.js"))
        for leaf in ("Cookies", "History", "Local Storage", "IndexedDB", "conversations"):
            protected.append(put(base / leaf / "state"))

    def run(*args, input=""):
        result = subprocess.run(
            ["/bin/zsh", str(SCRIPT), "--only", "browsers", *args],
            env=env, input=input, text=True, capture_output=True, timeout=30,
        )
        assert result.returncode == 0, result.stdout + result.stderr
        assert "ERROR" not in result.stdout, result.stdout
        return result.stdout

    preview = run("--dry-run", "--yes")
    assert "CachedExtensionVSIXs" in preview, "Попередній перегляд не містить кешів VSIX"
    for editor in EDITORS:
        if editor.startswith("Devin"):
            assert f"Clean {editor} caches?" in preview, f"Відсутній редактор {editor}"
    assert all(path.exists() for path in caches + protected)
    scan = run("--scan")
    assert "App cache: VS Code" in scan
    for editor in EDITORS:
        if editor.startswith("Devin"):
            assert f"App cache: {editor}" in scan
    assert all(path.exists() for path in caches + protected)
    run(input="n\n" * 20)
    run()
    assert all(path.exists() for path in caches + protected), "Відмова чи EOF змінили дані"
    if "Devin" in EDITORS:
        for process in (
            "/Applications/Devin.app/Contents/MacOS/Electron",
            "/Users/example/Applications/Devin.app/Contents/MacOS/Electron",
            "/Applications/Devin.app/Contents/Frameworks/Devin Helper.app/Contents/MacOS/Devin Helper",
            "/Applications/Devin - Next.app/Contents/MacOS/Electron",
        ):
            env["SMOKE_PROCESS"] = process
            active = "Devin - Next" if "Devin - Next.app" in process else "Devin"
            preview = run("--dry-run", "--yes")
            assert f"{active} is running, skipping its caches." in preview, process
            assert f"Clean {active} caches?" not in preview
        env["SMOKE_PROCESS"] = ""
    run("--yes")
    assert not any(path.exists() for path in caches), "Архіви VSIX залишилися"
    assert all(path.exists() for path in protected), "Змінено користувацькі дані"
    run("--yes")
    print("Редактори:", ", ".join(EDITORS))
    print("Сканування, попередній перегляд, відмова, EOF, захист процесів, очищення та повторний запуск — успішно")
