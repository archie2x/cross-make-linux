#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${TEST_DIR}/.." && pwd -P)"
status=0

if command -v shellcheck >/dev/null 2>&1; then
  printf 'Running shellcheck\n'
  shell_sources=()
  while IFS= read -r -d '' file; do
    shell_sources+=("$file")
  done < <(find "${REPO_ROOT}" -maxdepth 2 -name '*.sh' -print0)
  if [ ${#shell_sources[@]} -gt 0 ] &&
     ! shellcheck -x "${shell_sources[@]}"; then
    status=1
  fi
else
  printf 'Skipping shellcheck (binary not found)\n'
fi

for test_script in "${TEST_DIR}"/test_*.sh; do
  [ -f "${test_script}" ] || continue
  printf 'Running %s\n' "$(basename "${test_script}")"
  if ! "${test_script}"; then
    status=1
  fi
done

exit "${status}"
