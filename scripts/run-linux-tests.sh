#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: scripts/run-linux-tests.sh

Environment overrides:
  SWIFT_LINUX_IMAGE          Container image to use (default: swift:6.2-jammy)
  SWIFT_LINUX_PLATFORM       Container platform (default: linux/arm64)
  SWIFT_LINUX_MOUNT_TARGET   Container path for the repo (default: /workspace)
  SWIFT_LINUX_WORKDIR        Working directory in the container (default: /workspace)
  SWIFT_LINUX_CONTAINER_ARGS Extra container run args (string, split on spaces)
  SWIFT_LINUX_TEST_COMMAND   Command to run in the container (default: swift test)
USAGE
  exit 0
fi

if ! command -v container >/dev/null 2>&1; then
  echo "error: container CLI not found; install Apple Containerization and try again" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

image="${SWIFT_LINUX_IMAGE:-swift:6.2-jammy}"
platform="${SWIFT_LINUX_PLATFORM:-linux/arm64}"
mount_target="${SWIFT_LINUX_MOUNT_TARGET:-/workspace}"
workdir="${SWIFT_LINUX_WORKDIR:-$mount_target}"
extra_args=()
if [[ -n "${SWIFT_LINUX_CONTAINER_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  extra_args=(${SWIFT_LINUX_CONTAINER_ARGS})
fi

test_command="${SWIFT_LINUX_TEST_COMMAND:-swift test}"

container_script="$(cat <<'CONTAINER_SCRIPT'
set -euo pipefail
if ! command -v git >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y git
  else
    echo "error: git not available and apt-get not found" >&2
    exit 1
  fi
fi
CONTAINER_SCRIPT
)"
container_script+=$'\n'
container_script+="${test_command}"

run_args=(
  run
  --rm
  --mount "type=bind,source=${repo_root},target=${mount_target}"
  --workdir "${workdir}"
)

if [[ -n "${platform}" ]]; then
  run_args+=(--platform "${platform}")
fi

if [[ ${#extra_args[@]} -gt 0 ]]; then
  run_args+=("${extra_args[@]}")
fi

run_args+=("${image}" bash -lc "${container_script}")

container "${run_args[@]}"
