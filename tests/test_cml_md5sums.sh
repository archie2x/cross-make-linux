#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${TEST_DIR}/.." && pwd -P)"

# shellcheck source=../libexec/lib/common.sh disable=SC1091
. "${REPO_ROOT}/libexec/lib/common.sh"

orig_path="${PATH}"
rm_bin="$(command -v rm)"
tmp_dir="$(mktemp -d)"
trap 'PATH="${orig_path}"; "${rm_bin}" -rf "${tmp_dir}"' EXIT

pkg_dir="${tmp_dir}/pkg"
mkdir -p "${pkg_dir}/DEBIAN" "${pkg_dir}/usr/bin" "${pkg_dir}/lib"

echo 'hello' > "${pkg_dir}/usr/bin/tool"
printf 'data\n' > "${pkg_dir}/lib/blob"
# Ensure DEBIAN files are ignored
printf 'ignored' > "${pkg_dir}/DEBIAN/metadata"

cml_md5sums "${pkg_dir}"

md5_file="${pkg_dir}/DEBIAN/md5sums"
if [ ! -s "${md5_file}" ]; then
  echo "md5sums file not generated" >&2
  exit 1
fi

hash_tool="$(md5sum "${pkg_dir}/usr/bin/tool" | awk '{print $1}')"
hash_blob="$(md5sum "${pkg_dir}/lib/blob" | awk '{print $1}')"
expected_tool="${hash_tool}  usr/bin/tool"
expected_blob="${hash_blob}  lib/blob"

actual="$(cat "${md5_file}")"
if ! grep -qx "${expected_tool}" <<<"${actual}"; then
  echo "missing entry for usr/bin/tool" >&2
  exit 1
fi
if ! grep -qx "${expected_blob}" <<<"${actual}"; then
  echo "missing entry for lib/blob" >&2
  exit 1
fi

if grep -q 'metadata' "${md5_file}"; then
  echo "DEBIAN files should be excluded" >&2
  exit 1
fi
