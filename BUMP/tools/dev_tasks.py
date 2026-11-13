#!/usr/bin/env python3
"""Cross-platform task entrypoints for VS Code development tasks.

Ported from Sunshine Valley's tools/dev_tasks.py: the supervised live-sync stack
for the game, ArcEngine and BUMPResources, without Sunshine
Valley's Data Studio, Map Studio and content generators.

    python3 tools/dev_tasks.py dev-all            # everything; connect Studio Rojo to 127.0.0.1:1355
    python3 tools/dev_tasks.py dev-all --dry-run  # print what would run
    python3 tools/dev_tasks.py stop-dev
"""

from __future__ import annotations

import argparse
import json
import os
import posixpath
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
ENGINE_ROOT = (ROOT / "../../../ArcEngine").resolve()
RESOURCE_ROOT = Path(
    os.environ.get("BUMP_RESOURCES_ROOT", ROOT / "../BUMPResources")
).expanduser().resolve()
COMMON_ROOT = Path(os.path.commonpath([str(ROOT), str(ENGINE_ROOT), str(RESOURCE_ROOT)])).resolve()
GENERATED_ROJO_PROJECT = COMMON_ROOT / ".bump.rojo.project.json"
PID_FILE = COMMON_ROOT / ".bump.dev-pids.json"
# Another game's dev stack runs its own darklua watcher on ArcEngine/processed-src.
# Two watchers on one mirror race each other, so only one game's stack runs at a time.
OTHER_GAME_PID_FILES = (
    COMMON_ROOT / ".sunshinevalley.dev-pids.json",
    COMMON_ROOT / ".fightinasupermarket.dev-pids.json",
    COMMON_ROOT / ".smasharena.dev-pids.json",
    COMMON_ROOT / ".mecha.dev-pids.json",
    COMMON_ROOT / ".techdemos.dev-pids.json",
    COMMON_ROOT / ".destroyeverything.dev-pids.json",
    COMMON_ROOT / ".buildaboss.dev-pids.json",
    COMMON_ROOT / ".stealthesky.dev-pids.json",
    COMMON_ROOT / ".sillybillies.dev-pids.json",
    COMMON_ROOT / ".thescramble.dev-pids.json",
)
STUDIO_UIFUSION_IMPORT_HOT_RELOAD_ATTRIBUTE = "EnableStudioUIFusionImportHotReload"
DEV_SERVE_PORT = 1355
PYTHON = sys.executable or "python3"
REQUIRED_DEV_TOOLS = ("rojo", "darklua")
DARKLUA_SKIPPED_MODULE_PATTERNS = (
    "**/*.spec.lua",
)

# Only this repo's own helpers: Sunshine Valley's runner uses the same command
# shapes, so a generic pattern such as "darklua process --config" would stop it.
STOP_PATTERNS = [
    GENERATED_ROJO_PROJECT.name,
    str(ROOT / "tools" / "dev_tasks.py"),
]


@dataclass(frozen=True)
class RepoSpec:
    key: str
    label: str
    root: Path
    darklua_input: str
    darklua_output: str
    darklua_skip_files: tuple[str, ...] = ()
    prune_orphans: bool = False


@dataclass(frozen=True)
class ManagedCommand:
    label: str
    command: list[str]
    cwd: Path
    env: dict[str, str] | None = None


REPO_SPECS = {
    "game": RepoSpec(
        key="game",
        label="BUMP",
        root=ROOT,
        darklua_input="src",
        darklua_output="processed-src",
        darklua_skip_files=DARKLUA_SKIPPED_MODULE_PATTERNS,
        prune_orphans=True,
    ),
    "arc-engine": RepoSpec(
        key="arc-engine",
        label="ArcEngine",
        root=ENGINE_ROOT,
        darklua_input="src",
        darklua_output="processed-src",
        darklua_skip_files=DARKLUA_SKIPPED_MODULE_PATTERNS,
    ),
    "resources": RepoSpec(
        key="resources",
        label="BUMPResources",
        root=RESOURCE_ROOT,
        darklua_input="ResourceManager",
        darklua_output="processed-resources",
        darklua_skip_files=DARKLUA_SKIPPED_MODULE_PATTERNS,
    ),
}

REPO_PREPARATION_ORDER = ("arc-engine", "resources", "game")


def task_env(extra: dict[str, str] | None = None) -> dict[str, str]:
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"

    # GUI-launched editors on macOS do not always inherit the shell PATH.
    # Aftman installs its managed tool shims here, so include that directory
    # explicitly when it exists rather than requiring VS Code to be restarted
    # from a configured terminal.
    aftman_bin = Path.home() / ".aftman" / "bin"
    if aftman_bin.is_dir():
        path_entries = env.get("PATH", "").split(os.pathsep)
        if str(aftman_bin) not in path_entries:
            env["PATH"] = os.pathsep.join([str(aftman_bin), *path_entries])

    if extra:
        env.update(extra)
    return env


def call_process(command: list[str], *, cwd: Path = ROOT, env: dict[str, str] | None = None) -> int:
    """Run a child task while treating Ctrl+C as a normal stopped process."""

    try:
        return subprocess.call(command, cwd=cwd, env=task_env() if env is None else env)
    except KeyboardInterrupt:
        return 130
    except FileNotFoundError as exc:
        command_name = exc.filename or (command[0] if command else "unknown")
        print(
            f"[DevRunner] Command not found: {command_name}. "
            "Ensure it is installed and available on PATH.",
            flush=True,
        )
        return 127


def missing_commands(commands: Iterable[str], *, env: dict[str, str] | None = None) -> list[str]:
    resolved_env = task_env() if env is None else env
    search_path = resolved_env.get("PATH", "")
    return [command for command in commands if shutil.which(command, path=search_path) is None]


def validate_dev_tools() -> bool:
    missing = missing_commands(REQUIRED_DEV_TOOLS)
    if not missing:
        return True

    manifest = ROOT / "aftman.toml"
    print(f"[DevRunner] Missing required developer tool(s): {', '.join(missing)}.", flush=True)
    print(f"[DevRunner] Pinned tool versions are declared in {manifest}.", flush=True)
    print(f"[DevRunner] Install Aftman, then run `aftman install` from {ROOT}.", flush=True)
    return False


def require_path(path: Path, label: str) -> None:
    if not path.exists():
        raise FileNotFoundError(f"{label} does not exist: {path}")


def validate_dev_paths() -> None:
    for spec in REPO_SPECS.values():
        require_path(spec.root, spec.label)
        require_path(spec.root / "build.project.json", f"{spec.label} build.project.json")
        require_path(spec.root / "default.project.json", f"{spec.label} default.project.json")
        require_path(spec.root / "darklua.json", f"{spec.label} darklua.json")
        require_path(spec.root / spec.darklua_input, f"{spec.label} Darklua input")
    require_path(
        RESOURCE_ROOT / "client-resources.project.json",
        "BUMPResources client-resources.project.json",
    )


def atomic_publish_sourcemap(source: Path, destination: Path) -> None:
    """Validate and atomically publish a complete Rojo sourcemap."""

    source_bytes = source.read_bytes()
    json.loads(source_bytes.decode("utf-8-sig"))
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.",
        suffix=".publishing",
        dir=destination.parent,
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as temporary_file:
            temporary_file.write(source_bytes)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.replace(temporary_path, destination)
    finally:
        temporary_path.unlink(missing_ok=True)


def generate_sourcemap(spec: RepoSpec) -> bool:
    print(f"[DevRunner] Reconciling {spec.label} sourcemap...", flush=True)
    with tempfile.TemporaryDirectory(prefix=f"{spec.key}-sourcemap-") as directory:
        staging_path = Path(directory) / "sourcemap.json"
        result = call_process(
            ["rojo", "sourcemap", "default.project.json", "-o", str(staging_path)],
            cwd=spec.root,
        )
        if result != 0:
            print(f"[DevRunner] {spec.label} sourcemap reconciliation failed with code {result}.", flush=True)
            return False
        try:
            atomic_publish_sourcemap(staging_path, spec.root / "sourcemap.json")
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            print(f"[DevRunner] {spec.label} sourcemap publication failed: {exc}", flush=True)
            return False

    print(f"[DevRunner] {spec.label} sourcemap is complete.", flush=True)
    return True


def run_rojo_sourcemap_watch(args: argparse.Namespace) -> int:
    """Publish Rojo's watched sourcemap snapshots without exposing partial JSON."""

    repository_root = Path.cwd()
    output_path = (repository_root / args.output).resolve()
    with tempfile.TemporaryDirectory(prefix="rojo-sourcemap-watch-") as directory:
        staging_path = Path(directory) / output_path.name
        command = ["rojo", "sourcemap", args.project, "-o", str(staging_path), "--watch"]
        try:
            process = subprocess.Popen(
                command,
                cwd=repository_root,
                env=task_env(),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
        except FileNotFoundError as exc:
            command_name = exc.filename or command[0]
            print(f"[DevRunner] Command not found: {command_name}.", flush=True)
            return 127

        assert process.stdout is not None
        try:
            for line in iter(process.stdout.readline, ""):
                if not line:
                    break
                print(line, end="" if line.endswith("\n") else "\n", flush=True)
                if "Created sourcemap at" not in line:
                    continue
                try:
                    atomic_publish_sourcemap(staging_path, output_path)
                except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
                    print(f"[DevRunner] Sourcemap publication failed: {exc}", flush=True)
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                    return 1
                print(f"[DevRunner] Published sourcemap: {output_path}", flush=True)
            return process.wait()
        except KeyboardInterrupt:
            return 130
        finally:
            process.stdout.close()
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def darklua_process_command(spec: RepoSpec, *, watch: bool = False) -> list[str]:
    command = ["darklua", "process", "--config", "./darklua.json", spec.darklua_input, spec.darklua_output]
    if watch:
        command.append("--watch")
    return command


def preparation_specs_for(repo_key: str) -> tuple[RepoSpec, ...]:
    keys = REPO_PREPARATION_ORDER if repo_key == "game" else (repo_key,)
    return tuple(REPO_SPECS[key] for key in keys)


def processed_module_sources(spec: RepoSpec) -> list[Path]:
    source_root = spec.root / spec.darklua_input
    sources: list[Path] = []
    for source_path in source_root.rglob("*"):
        if not source_path.is_file() or source_path.suffix.lower() not in (".lua", ".luau"):
            continue
        relative_path = source_path.relative_to(source_root)
        candidate = PurePosixPath(relative_path.as_posix())
        if any(
            candidate.match(pattern)
            or (pattern.startswith("**/") and candidate.match(pattern.removeprefix("**/")))
            for pattern in spec.darklua_skip_files
        ):
            continue
        sources.append(relative_path)
    return sorted(sources)


def missing_processed_modules(spec: RepoSpec) -> list[Path]:
    output_root = spec.root / spec.darklua_output
    return [
        relative_path
        for relative_path in processed_module_sources(spec)
        if not (output_root / relative_path).is_file()
    ]


def stale_processed_modules(spec: RepoSpec, *, settle_seconds: float, now: float | None = None) -> list[Path]:
    """Modules whose processed copy is missing or older than a settled source file.

    Sources touched within `settle_seconds` are left to the Darklua watcher so
    the repair loop only picks up saves the watcher actually dropped.
    """

    source_root = spec.root / spec.darklua_input
    output_root = spec.root / spec.darklua_output
    current_time = time.time() if now is None else now
    stale: list[Path] = []
    for relative_path in processed_module_sources(spec):
        try:
            source_mtime = (source_root / relative_path).stat().st_mtime
        except FileNotFoundError:
            continue
        if current_time - source_mtime < settle_seconds:
            continue
        try:
            output_mtime = (output_root / relative_path).stat().st_mtime
        except FileNotFoundError:
            stale.append(relative_path)
            continue
        if output_mtime < source_mtime:
            stale.append(relative_path)
    return stale


def orphaned_processed_modules(spec: RepoSpec) -> list[Path]:
    """Processed modules whose source is gone.

    Darklua only ever writes, so deleting a source leaves its output behind, and
    Rojo keeps serving that output to Studio.
    """

    source_root = spec.root / spec.darklua_input
    output_root = spec.root / spec.darklua_output
    orphans: list[Path] = []
    for output_path in output_root.rglob("*"):
        if not output_path.is_file() or output_path.suffix.lower() not in (".lua", ".luau"):
            continue
        relative_path = output_path.relative_to(output_root)
        if not (source_root / relative_path).is_file():
            orphans.append(relative_path)
    return sorted(orphans)


def prune_processed_modules(spec: RepoSpec, relative_paths: Iterable[Path]) -> int:
    # Files only: deleting a folder Rojo is watching crashes Rojo 7.7, and an empty folder is harmless.
    output_root = spec.root / spec.darklua_output
    pruned = 0
    for relative_path in relative_paths:
        (output_root / relative_path).unlink(missing_ok=True)
        print(f"[DevRunner] {spec.label} pruned {relative_path.as_posix()}", flush=True)
        pruned += 1
    return pruned


def repair_processed_modules(spec: RepoSpec, relative_paths: Iterable[Path]) -> int:
    repaired = 0
    for relative_path in relative_paths:
        source = PurePosixPath(spec.darklua_input, relative_path.as_posix())
        output = PurePosixPath(spec.darklua_output, relative_path.as_posix())
        result = call_process(
            ["darklua", "process", "--config", "./darklua.json", str(source), str(output)],
            cwd=spec.root,
            env=task_env({"ROBLOX_DEV": "true"}),
        )
        if result != 0:
            print(f"[DarkluaRepair] {spec.label} failed to process {relative_path.as_posix()} ({result}).", flush=True)
            continue
        output_path = spec.root / output
        source_path = spec.root / source
        try:
            # Keep the output at least as new as its source so an unchanged
            # rewrite is not picked up again on the next poll.
            if output_path.stat().st_mtime < source_path.stat().st_mtime:
                os.utime(output_path)
        except FileNotFoundError:
            continue
        print(f"[DarkluaRepair] {spec.label} restored {relative_path.as_posix()}", flush=True)
        repaired += 1
    return repaired


def run_darklua_mirror_repair(args: argparse.Namespace) -> int:
    """Backstop for `darklua --watch`, which drops outputs on atomic (rename) saves."""

    spec = REPO_SPECS[args.repo]
    print(f"[DarkluaRepair] Watching {spec.label} {spec.darklua_output} for dropped modules.", flush=True)
    orphans_last_poll: set[Path] = set()
    try:
        while True:
            stale = stale_processed_modules(spec, settle_seconds=args.settle)
            if stale:
                repair_processed_modules(spec, stale)
            if spec.prune_orphans:
                # An atomic save briefly hides a source, so an orphan has to last two polls.
                orphans = set(orphaned_processed_modules(spec))
                prune_processed_modules(spec, sorted(orphans & orphans_last_poll))
                orphans_last_poll = orphans
            time.sleep(args.interval)
    except KeyboardInterrupt:
        return 0


def reconcile_processed_mirror(spec: RepoSpec) -> bool:
    print(f"[DevRunner] Reconciling {spec.label} processed mirror...", flush=True)
    result = call_process(darklua_process_command(spec), cwd=spec.root, env=task_env({"ROBLOX_DEV": "true"}))
    if result != 0:
        print(f"[DevRunner] {spec.label} Darklua reconciliation failed with code {result}.", flush=True)
        return False

    if spec.prune_orphans:
        prune_processed_modules(spec, orphaned_processed_modules(spec))

    missing = missing_processed_modules(spec)
    if missing:
        print(f"[DevRunner] {spec.label} processed mirror is missing {len(missing)} Luau module(s):", flush=True)
        for relative_path in missing:
            print(f"[DevRunner]   {relative_path.as_posix()}", flush=True)
        return False

    print(f"[DevRunner] {spec.label} processed mirror is complete.", flush=True)
    return True


def reconcile_generated_outputs(specs: Iterable[RepoSpec]) -> bool:
    for spec in specs:
        if not generate_sourcemap(spec):
            return False
        if not reconcile_processed_mirror(spec):
            return False
    return True


def relative_project_path(path: Path, base: Path) -> str:
    return os.path.relpath(path.resolve(), base.resolve()).replace(os.sep, "/")


def enable_studio_uifusion_import_hot_reload(project: dict) -> dict:
    """Opt the generated dev-all Rojo project into UIFusion import reloads."""

    try:
        replicated_storage = project["tree"]["ReplicatedStorage"]
    except (KeyError, TypeError) as exc:
        raise ValueError("Generated Rojo project has no ReplicatedStorage tree.") from exc
    if not isinstance(replicated_storage, dict):
        raise ValueError("Generated Rojo project ReplicatedStorage tree must be an object.")

    attributes = replicated_storage.get("$attributes")
    if attributes is None:
        attributes = {}
        replicated_storage["$attributes"] = attributes
    elif not isinstance(attributes, dict):
        raise ValueError("Generated Rojo project ReplicatedStorage.$attributes must be an object.")

    attributes[STUDIO_UIFUSION_IMPORT_HOT_RELOAD_ATTRIBUTE] = True
    return project


def rewrite_rojo_glob_path(pattern: str, original_root: Path, new_root: Path) -> str:
    """Keep a Rojo ignore pattern pointed at the same source after project relocation."""

    normalized = pattern.replace("\\", "/")
    # Recursive basename patterns are intentionally project-wide. Once dev-all
    # relocates the project to COMMON_ROOT, this also filters sibling repos.
    if normalized.startswith("**/"):
        return normalized

    original_prefix = relative_project_path(original_root, new_root)
    return posixpath.normpath(posixpath.join(original_prefix, normalized))


def rewrite_rojo_paths(value, original_root: Path, new_root: Path):
    if isinstance(value, dict):
        rewritten = {}
        for key, item in value.items():
            if key == "$path" and isinstance(item, str):
                absolute_path = (original_root / item).resolve()
                rewritten[key] = relative_project_path(absolute_path, new_root)
            elif key == "globIgnorePaths" and isinstance(item, list):
                rewritten[key] = [
                    rewrite_rojo_glob_path(pattern, original_root, new_root) if isinstance(pattern, str) else pattern
                    for pattern in item
                ]
            else:
                rewritten[key] = rewrite_rojo_paths(item, original_root, new_root)
        return rewritten

    if isinstance(value, list):
        return [rewrite_rojo_paths(item, original_root, new_root) for item in value]

    return value


def build_common_rojo_project() -> dict:
    with (ROOT / "build.project.json").open("r", encoding="utf-8") as project_file:
        project = json.load(project_file)

    rewritten = rewrite_rojo_paths(project, ROOT, COMMON_ROOT)
    enable_studio_uifusion_import_hot_reload(rewritten)
    rewritten["servePort"] = DEV_SERVE_PORT
    return rewritten


def write_common_rojo_project(project: dict) -> None:
    GENERATED_ROJO_PROJECT.write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8")


def repo_serve_port(spec: RepoSpec) -> int:
    with (spec.root / "build.project.json").open("r", encoding="utf-8") as project_file:
        project = json.load(project_file)
    return int(project.get("servePort") or 34872)


def repo_watch_commands(spec: RepoSpec, include_rojo: bool) -> list[ManagedCommand]:
    commands: list[ManagedCommand] = []
    if include_rojo:
        commands.append(
            ManagedCommand(
                label=f"{spec.label}:rojo",
                command=["rojo", "serve", "build.project.json"],
                cwd=spec.root,
                env=task_env(),
            )
        )

    commands.extend(
        [
            ManagedCommand(
                label=f"{spec.label}:sourcemap",
                command=[
                    PYTHON,
                    str(ROOT / "tools" / "dev_tasks.py"),
                    "rojo-sourcemap-watch",
                    "--project",
                    "default.project.json",
                    "--output",
                    "sourcemap.json",
                ],
                cwd=spec.root,
                env=task_env(),
            ),
            ManagedCommand(
                label=f"{spec.label}:darklua",
                command=darklua_process_command(spec, watch=True),
                cwd=spec.root,
                env=task_env({"ROBLOX_DEV": "true"}),
            ),
            ManagedCommand(
                label=f"{spec.label}:darklua-repair",
                command=[PYTHON, str(ROOT / "tools" / "dev_tasks.py"), "darklua-mirror-repair", "--repo", spec.key],
                cwd=spec.root,
                env=task_env(),
            ),
        ]
    )
    return commands


def repo_keys(shared_engine: bool) -> tuple[str, ...]:
    """With --shared-engine another game's stack owns ArcEngine's mirror, so leave it alone."""

    return ("game", "resources") if shared_engine else ("game", "arc-engine", "resources")


def dev_all_commands(shared_engine: bool = False) -> list[ManagedCommand]:
    commands = [
        ManagedCommand(
            label="BUMP:rojo",
            command=["rojo", "serve", str(GENERATED_ROJO_PROJECT)],
            cwd=ROOT,
            env=task_env(),
        )
    ]
    for key in repo_keys(shared_engine):
        commands.extend(repo_watch_commands(REPO_SPECS[key], include_rojo=False))
    return commands


def print_dry_run(commands: list[ManagedCommand], project: dict | None = None) -> None:
    print(f"[DevRunner] Game repo: {ROOT}", flush=True)
    print(f"[DevRunner] Engine repo: {ENGINE_ROOT}", flush=True)
    print(f"[DevRunner] Resources repo: {RESOURCE_ROOT}", flush=True)
    print(f"[DevRunner] Common project root: {COMMON_ROOT}", flush=True)
    if project is not None:
        print(f"[DevRunner] Would write generated Rojo project: {GENERATED_ROJO_PROJECT}", flush=True)
        print(f"[DevRunner] Connect Studio Rojo to 127.0.0.1:{DEV_SERVE_PORT}", flush=True)
    print(
        "[DevRunner] Would reconcile sourcemaps and processed mirrors in dependency order before starting watchers.",
        flush=True,
    )
    for command in commands:
        command_text = " ".join(command.command)
        print(f"[DevRunner] Would start {command.label}: {command_text} (cwd: {command.cwd})", flush=True)


def pid_exists(pid: int) -> bool:
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes

        process_query_limited_information = 0x1000
        still_active = 259
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

        handle = kernel32.OpenProcess(process_query_limited_information, False, pid)
        if not handle:
            return ctypes.get_last_error() == 5  # ERROR_ACCESS_DENIED means the PID exists.

        try:
            exit_code = wintypes.DWORD()
            if not kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code)):
                return True
            return exit_code.value == still_active
        finally:
            kernel32.CloseHandle(handle)

    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False


def running_other_game_stack() -> Path | None:
    """The PID file of another game's live dev stack, if one is running."""

    for pid_file in OTHER_GAME_PID_FILES:
        try:
            payload = json.loads(pid_file.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        try:
            owner = int(payload.get("owner") or 0)
        except (TypeError, ValueError):
            continue
        if pid_exists(owner):
            return pid_file
    return None


def signal_process_group(pid: int, sig: int) -> bool:
    try:
        if os.name == "nt":
            os.kill(pid, sig)
        else:
            os.killpg(pid, sig)
        return True
    except ProcessLookupError:
        return False
    except PermissionError as exc:
        print(f"[DevRunner] Could not signal process group {pid}: {exc}", flush=True)
        return False


def terminate_windows_tree(pid: int, force: bool, log_errors: bool = True) -> bool:
    args = ["taskkill", "/PID", str(pid), "/T"]
    if force:
        args.append("/F")
    result = subprocess.run(args, check=False, capture_output=True, text=True)
    if log_errors and result.returncode != 0 and result.stderr.strip():
        print(result.stderr.strip(), flush=True)
    return result.returncode == 0


def terminate_pid_group(pid: int, force: bool = False) -> bool:
    if os.name == "nt":
        if force:
            return terminate_windows_tree(pid, force=True)
        ctrl_break = getattr(signal, "CTRL_BREAK_EVENT", signal.SIGTERM)
        try:
            os.kill(pid, ctrl_break)
            return True
        except Exception:
            return terminate_windows_tree(pid, force=False, log_errors=False)

    return signal_process_group(pid, signal.SIGKILL if force else signal.SIGTERM)


def stop_managed_processes(remove_file: bool = True) -> bool:
    if not PID_FILE.exists():
        return False

    try:
        payload = json.loads(PID_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"[DevStop] Ignoring invalid PID file {PID_FILE}: {exc}", flush=True)
        if remove_file:
            PID_FILE.unlink(missing_ok=True)
        return False

    processes = payload.get("processes")
    if not isinstance(processes, list):
        if remove_file:
            PID_FILE.unlink(missing_ok=True)
        return False

    stopped = False
    for entry in processes:
        if not isinstance(entry, dict):
            continue
        pid = entry.get("pid")
        label = entry.get("label", "managed")
        if not isinstance(pid, int) or pid == os.getpid():
            continue
        if not pid_exists(pid):
            continue
        print(f"[DevStop] Stopping managed {label} {pid}", flush=True)
        stopped = terminate_pid_group(pid) or stopped

    time.sleep(0.7)
    for entry in processes:
        if not isinstance(entry, dict):
            continue
        pid = entry.get("pid")
        if not isinstance(pid, int) or pid == os.getpid() or not pid_exists(pid):
            continue
        if terminate_pid_group(pid, force=True):
            print(f"[DevStop] Force stopped managed {pid}", flush=True)
            stopped = True

    owner_pid = payload.get("owner")
    if isinstance(owner_pid, int) and owner_pid not in (os.getpid(), os.getppid()) and pid_exists(owner_pid):
        print(f"[DevStop] Stopping managed supervisor {owner_pid}", flush=True)
        stopped = terminate_pid_group(owner_pid) or stopped
        time.sleep(0.3)
        if pid_exists(owner_pid) and terminate_pid_group(owner_pid, force=True):
            print(f"[DevStop] Force stopped managed supervisor {owner_pid}", flush=True)
            stopped = True

    if remove_file:
        PID_FILE.unlink(missing_ok=True)
    return stopped


def write_pid_file(records: list[dict]) -> None:
    payload = {
        "owner": os.getpid(),
        "createdAt": time.time(),
        "generatedRojoProject": str(GENERATED_ROJO_PROJECT),
        "processes": [
            {
                "pid": record["process"].pid,
                "label": record["label"],
                "cwd": str(record["command"].cwd),
                "command": record["command"].command,
            }
            for record in records
        ],
    }
    temp_path = PID_FILE.with_suffix(".tmp")
    temp_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    temp_path.replace(PID_FILE)


def prefix_output(label: str, stream) -> None:
    try:
        for line in iter(stream.readline, ""):
            if not line:
                break
            print(f"[{label}] {line}", end="" if line.endswith("\n") else "\n", flush=True)
    finally:
        stream.close()


def start_managed_command(command: ManagedCommand) -> dict:
    kwargs = {
        "cwd": command.cwd,
        "env": command.env or task_env(),
        "stdout": subprocess.PIPE,
        "stderr": subprocess.STDOUT,
        "text": True,
        "bufsize": 1,
    }
    if os.name == "nt":
        kwargs["creationflags"] = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    else:
        kwargs["start_new_session"] = True

    process = subprocess.Popen(command.command, **kwargs)
    assert process.stdout is not None
    thread = threading.Thread(target=prefix_output, args=(command.label, process.stdout), daemon=True)
    thread.start()
    return {"label": command.label, "command": command, "process": process, "thread": thread}


def terminate_records(records: list[dict]) -> None:
    for record in records:
        process = record["process"]
        if process.poll() is None:
            print(f"[DevRunner] Stopping {record['label']} {process.pid}", flush=True)
            terminate_pid_group(process.pid)

    deadline = time.monotonic() + 5
    for record in records:
        process = record["process"]
        remaining = max(0.0, deadline - time.monotonic())
        try:
            process.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            if terminate_pid_group(process.pid, force=True):
                print(f"[DevRunner] Force stopped {record['label']} {process.pid}", flush=True)

    for record in records:
        try:
            record["thread"].join(timeout=1)
        except RuntimeError:
            pass


def supervise(commands: list[ManagedCommand]) -> int:
    records: list[dict] = []
    shutdown_requested = {"value": False}
    previous_handlers = {}

    def handle_signal(signum, _frame):
        print(f"[DevRunner] Received signal {signum}; shutting down.", flush=True)
        shutdown_requested["value"] = True

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            previous_handlers[sig] = signal.getsignal(sig)
            signal.signal(sig, handle_signal)
        except (OSError, ValueError):
            pass

    try:
        for command in commands:
            print(f"[DevRunner] Starting {command.label}: {' '.join(command.command)}", flush=True)
            records.append(start_managed_command(command))
        write_pid_file(records)

        while True:
            if shutdown_requested["value"]:
                return 0

            for record in records:
                return_code = record["process"].poll()
                if return_code is None:
                    continue

                print(
                    f"[DevRunner] {record['label']} exited with code {return_code}; stopping remaining processes.",
                    flush=True,
                )
                return return_code if return_code != 0 else 1

            time.sleep(0.25)
    except KeyboardInterrupt:
        print("[DevRunner] Interrupted; shutting down.", flush=True)
        return 0
    except FileNotFoundError as exc:
        print(f"[DevRunner] Could not start process: {exc}", flush=True)
        return 1
    finally:
        terminate_records(records)
        PID_FILE.unlink(missing_ok=True)
        for sig, previous_handler in previous_handlers.items():
            try:
                signal.signal(sig, previous_handler)
            except (OSError, ValueError):
                pass


def read_processes() -> list[tuple[int, str, str]]:
    if os.name == "nt":
        try:
            result = subprocess.run(
                [
                    "powershell.exe",
                    "-NoProfile",
                    "-Command",
                    "Get-CimInstance Win32_Process | Select-Object ProcessId,Name,CommandLine | ConvertTo-Json -Compress",
                ],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
                timeout=8,
            )
        except subprocess.TimeoutExpired:
            print("[DevStop] Windows process scan timed out; managed processes were already checked.", flush=True)
            return []
        if result.returncode != 0:
            print(result.stderr.strip(), flush=True)
            return []
        try:
            raw_processes = json.loads(result.stdout or "[]")
        except json.JSONDecodeError as exc:
            print(f"[DevStop] Could not parse Windows process list: {exc}", flush=True)
            return []
        if isinstance(raw_processes, dict):
            raw_processes = [raw_processes]

        processes: list[tuple[int, str, str]] = []
        for process_info in raw_processes:
            if not isinstance(process_info, dict):
                continue
            try:
                pid = int(process_info.get("ProcessId"))
            except (TypeError, ValueError):
                continue
            command_name = str(process_info.get("Name") or "")
            command_line = str(process_info.get("CommandLine") or command_name)
            processes.append((pid, command_name, command_line))
        return processes

    result = subprocess.run(["ps", "-axo", "pid=,command="], cwd=ROOT, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr.strip(), flush=True)
        return []

    processes = []
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) < 2:
            continue
        try:
            pid = int(parts[0])
        except ValueError:
            continue
        command_line = parts[1]
        command_name = Path(command_line.split(None, 1)[0]).name
        processes.append((pid, command_name, command_line))
    return processes


def should_stop_process(pid: int, command_line: str) -> bool:
    if pid == os.getpid() or pid == os.getppid():
        return False
    return any(pattern in command_line for pattern in STOP_PATTERNS)


def terminate_process(pid: int) -> bool:
    if os.name == "nt":
        return terminate_windows_tree(pid, force=False, log_errors=False)
    try:
        os.kill(pid, signal.SIGTERM)
        return True
    except ProcessLookupError:
        return False
    except PermissionError as exc:
        print(f"[DevStop] Could not stop {pid}: {exc}", flush=True)
        return False


def stop_legacy_processes() -> bool:
    targets = [
        (pid, command_name)
        for pid, command_name, command_line in read_processes()
        if should_stop_process(pid, command_line)
    ]
    stopped = False
    for pid, command_name in sorted(targets, reverse=True):
        print(f"[DevStop] Stopping {command_name} {pid}", flush=True)
        if terminate_process(pid):
            stopped = True
    return stopped


def cleanup_existing_dev_processes() -> None:
    stop_managed_processes()
    stop_legacy_processes()


def refuse_if_other_game_running(prefix: str) -> bool:
    other = running_other_game_stack()
    if other is None:
        return False
    print(f"[{prefix}] Another game's dev stack is running ({other}).", flush=True)
    print(
        f"[{prefix}] It owns the ArcEngine darklua watcher. Stop it first, "
        "e.g. `python3 tools/dev_tasks.py stop-dev` in that game's repo.",
        flush=True,
    )
    return True


def run_dev_all(args: argparse.Namespace) -> int:
    try:
        validate_dev_paths()
        project = build_common_rojo_project()
    except Exception as exc:
        print(f"[DevAll] Configuration error: {exc}", flush=True)
        return 1

    commands = dev_all_commands(args.shared_engine)
    if args.dry_run:
        print_dry_run(commands, project)
        return 0

    if not validate_dev_tools():
        return 1
    if not args.shared_engine and refuse_if_other_game_running("DevAll"):
        return 1

    cleanup_existing_dev_processes()
    if not reconcile_generated_outputs(REPO_SPECS[key] for key in REPO_PREPARATION_ORDER if key in repo_keys(args.shared_engine)):
        print("[DevAll] Generated output preparation failed; watchers were not started.", flush=True)
        return 1
    write_common_rojo_project(project)
    print(f"[DevAll] Generated Rojo project: {GENERATED_ROJO_PROJECT}", flush=True)
    print(f"[DevAll] Connect Studio Rojo to 127.0.0.1:{DEV_SERVE_PORT}", flush=True)
    return supervise(commands)


def run_dev_repo(args: argparse.Namespace) -> int:
    try:
        validate_dev_paths()
        spec = REPO_SPECS[args.repo]
        port = repo_serve_port(spec)
    except Exception as exc:
        print(f"[DevRepo] Configuration error: {exc}", flush=True)
        return 1

    commands = repo_watch_commands(spec, include_rojo=True)
    if args.dry_run:
        print_dry_run(commands)
        print(f"[DevRepo] Connect Studio Rojo to 127.0.0.1:{port}", flush=True)
        return 0

    if not validate_dev_tools():
        return 1
    if refuse_if_other_game_running("DevRepo"):
        return 1

    cleanup_existing_dev_processes()
    if not reconcile_generated_outputs(preparation_specs_for(args.repo)):
        print("[DevRepo] Generated output preparation failed; watchers were not started.", flush=True)
        return 1
    print(f"[DevRepo] Connect Studio Rojo to 127.0.0.1:{port}", flush=True)
    return supervise(commands)


def run_prepare(args: argparse.Namespace) -> int:
    """One-shot sourcemaps and processed mirrors for all three repos, no watchers."""

    try:
        validate_dev_paths()
    except Exception as exc:
        print(f"[Prepare] Configuration error: {exc}", flush=True)
        return 1
    if not validate_dev_tools():
        return 1
    if not args.shared_engine and refuse_if_other_game_running("Prepare"):
        return 1
    keys = repo_keys(args.shared_engine)
    return 0 if reconcile_generated_outputs(REPO_SPECS[key] for key in REPO_PREPARATION_ORDER if key in keys) else 1


def run_stop_dev(args: argparse.Namespace) -> int:
    if stop_managed_processes():
        return 0

    if not args.legacy:
        print(f"[DevStop] No active managed dev stack found at {PID_FILE}.", flush=True)
        print("[DevStop] Use stop-dev --legacy to scan for orphaned watcher processes.", flush=True)
        return 0

    if not stop_legacy_processes():
        print("[DevStop] No matching dev processes found.", flush=True)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run BUMP development tasks.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    dev_all = subparsers.add_parser("dev-all", help="Run the supervised live-sync stack (game + engine + resources).")
    dev_all.add_argument("--dry-run", action="store_true", help="Validate and print commands without starting watchers.")
    dev_all.add_argument("--shared-engine", action="store_true", help="Leave ArcEngine's mirror to another game's running stack.")
    dev_all.set_defaults(func=run_dev_all)

    dev_repo = subparsers.add_parser("dev-repo", help="Run one standalone repo live-sync stack.")
    dev_repo.add_argument("repo", choices=sorted(REPO_SPECS))
    dev_repo.add_argument("--dry-run", action="store_true", help="Validate and print commands without starting watchers.")
    dev_repo.set_defaults(func=run_dev_repo)

    prepare = subparsers.add_parser("prepare", help="Regenerate sourcemaps and processed mirrors once, without watchers.")
    prepare.add_argument("--shared-engine", action="store_true", help="Leave ArcEngine's mirror to another game's running stack.")
    prepare.set_defaults(func=run_prepare)

    sourcemap_watch = subparsers.add_parser(
        "rojo-sourcemap-watch", help="Watch a Rojo project and atomically publish complete sourcemaps."
    )
    sourcemap_watch.add_argument("--project", default="default.project.json")
    sourcemap_watch.add_argument("--output", default="sourcemap.json")
    sourcemap_watch.set_defaults(func=run_rojo_sourcemap_watch)

    darklua_repair = subparsers.add_parser(
        "darklua-mirror-repair", help="Restore processed modules that the Darklua watcher dropped."
    )
    darklua_repair.add_argument("--repo", choices=sorted(REPO_SPECS), required=True)
    darklua_repair.add_argument("--interval", type=float, default=2.0, help="Seconds between scans.")
    darklua_repair.add_argument("--settle", type=float, default=1.5, help="Seconds a save is left to the watcher.")
    darklua_repair.set_defaults(func=run_darklua_mirror_repair)

    stop_dev = subparsers.add_parser("stop-dev", help="Stop this game's development processes.")
    stop_dev.add_argument("--legacy", action="store_true", help="Scan process command lines for orphaned dev processes.")
    stop_dev.set_defaults(func=run_stop_dev)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
