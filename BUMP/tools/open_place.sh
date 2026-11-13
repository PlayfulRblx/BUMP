#!/bin/zsh
# Builds the whole game into a place file and opens it in Studio, replacing a copy opened this way.
# The file needs a path with no spaces: Studio stays on its start page otherwise. Unpublished is
# fine, and the Studio tools can drive it. Run from anywhere, then press Play.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMON="$(cd "$ROOT/../../.." && pwd)"
PLACE="${${TMPDIR:-/tmp}%/}/BUMP.rbxl"
python3 "$ROOT/tools/dev_tasks.py" prepare --shared-engine
python3 - "$ROOT" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dev_tasks", sys.argv[1] + "/tools/dev_tasks.py")
tasks = importlib.util.module_from_spec(spec)
sys.modules["dev_tasks"] = tasks
spec.loader.exec_module(tasks)
tasks.write_common_rojo_project(tasks.build_common_rojo_project())
PY
(cd "$COMMON" && "$HOME/.aftman/bin/rojo" build .bump.rojo.project.json -o "$PLACE")
pkill -f "localPlaceFile $PLACE" 2>/dev/null || true
nohup /Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio -task EditFile -localPlaceFile "$PLACE" >/dev/null 2>&1 &
disown
echo "Opening $PLACE"
