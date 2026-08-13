#!/usr/bin/env bash
# Idempotent Cloud Agent install for Arize Phoenix.
#
# Phoenix 4.12.0 pins several dependencies (e.g. strawberry-graphql==0.235.0)
# and leaves others unpinned. On modern Python those unpinned deps resolve to
# versions that are incompatible with Phoenix. CI runs on Python 3.8, which
# caps the resolver to the contemporaneous, mutually-compatible releases, so we
# mirror that here using a uv-managed Python 3.8 interpreter.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

PY_VERSION="3.8"
SQLEAN_PIN="sqlean.py==3.45.1"   # newest release with a cp38 wheel (newer ones ship a broken sdist)

# --- uv (Python toolchain manager) ---------------------------------------
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"

# --- Python 3.8 backend venv ---------------------------------------------
uv python install "$PY_VERSION"
if [ ! -x ".venv/bin/python" ]; then
  uv venv --python "$PY_VERSION" .venv
fi

# sqlean.py must be pinned before the editable install so its cp38 wheel is used
# instead of the newer, source-only (and broken) distribution.
uv pip install --python .venv "$SQLEAN_PIN"

# Core Phoenix (editable) — this is what runs the server.
uv pip install --python .venv -e "."

# Dev toolchain: linting, type-checking, and the test runner + drivers/helpers
# used by the bulk of the suite. Heavy LLM-integration extras (litellm, arize,
# tokenizers, ...) are intentionally omitted because they lack Python 3.8 wheels
# and are not needed to run Phoenix; install them on demand when needed.
uv pip install --python .venv \
  "ruff==0.4.9" "mypy==1.10.0" \
  "pytest==8.2.2" pytest-asyncio pytest-cov pytest-postgresql \
  asyncpg "psycopg[binary]" \
  responses respx nest-asyncio tenacity \
  "pandas-stubs==2.0.3.230814" types-tabulate types-psutil types-tqdm \
  types-protobuf types-setuptools types-cachetools

# --- Web app -------------------------------------------------------------
# Vite builds into src/phoenix/server/static, which the Python server serves.
# The lockfile is pnpm v6 format, so pin pnpm 8 via corepack and disable its
# interactive download prompt to keep the install non-interactive.
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
corepack enable >/dev/null 2>&1 || true
corepack prepare pnpm@8.15.9 --activate
pushd app >/dev/null
pnpm install --frozen-lockfile
pnpm run build
popd >/dev/null

echo "Phoenix install complete. Run the server with: .venv/bin/python -m phoenix.server.main serve"
