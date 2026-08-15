#!/usr/bin/env bash
# Idempotent Cloud Agent install for Arize Phoenix.
#
# Phoenix 4.12.0 pins a few dependencies (e.g. strawberry-graphql==0.235.0) but
# leaves most unpinned. Installed today on a modern interpreter, those unpinned
# deps resolve to versions that are incompatible with Phoenix (pydantic>=2.10,
# uvicorn>=0.30, starlette>=0.38, setuptools>=80, ...). Instead of pinning each
# one, we resolve the whole dependency graph as of just after the 4.12.0 release
# using uv's --exclude-newer, which reproduces the versions Phoenix was built
# against. Python 3.11 matches the production Dockerfile.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

PY_VERSION="3.11"
EXCLUDE_NEWER="2024-07-19"   # arize-phoenix 4.12.0 was released 2024-07-18

# --- uv (Python toolchain manager) ---------------------------------------
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"

# --- Python 3.11 backend venv --------------------------------------------
uv python install "$PY_VERSION"
if [ ! -x ".venv/bin/python" ]; then
  uv venv --python "$PY_VERSION" .venv
fi

COMMON=(--python .venv --exclude-newer "$EXCLUDE_NEWER")

# Core Phoenix (editable) plus setuptools, which Phoenix imports at runtime
# (pkg_resources). setuptools resolved at the cutoff still ships pkg_resources.
uv pip install "${COMMON[@]}" -e "." setuptools

# Dev toolchain: linting, type-checking, and the test runner + drivers/helpers
# used by the bulk of the suite. Heavy LLM-integration extras (litellm, arize,
# tokenizers, ...) are intentionally omitted; install them on demand if needed.
uv pip install "${COMMON[@]}" \
  "ruff==0.4.9" "mypy==1.10.0" \
  "pytest==8.2.2" pytest-asyncio pytest-cov pytest-postgresql \
  asyncpg "psycopg[binary]" \
  responses respx nest-asyncio tenacity \
  pydantic \
  pandas-stubs types-tabulate types-psutil types-tqdm \
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
