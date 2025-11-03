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

brew_prefix="${tmp_dir}/brew-prefix"

cellar_sed="${tmp_dir}/cellar/gnu-sed/1.0"
mkdir -p "${cellar_sed}/libexec/gnubin"
mkdir -p "${brew_prefix}/opt"
ln -s "${cellar_sed}" "${brew_prefix}/opt/gnu-sed"
ln -s "${cellar_sed}" "${brew_prefix}/opt/gsed"

cellar_find="${tmp_dir}/cellar/findutils/1.0"
mkdir -p "${cellar_find}/libexec/gnubin"
ln -s "${cellar_find}" "${brew_prefix}/opt/findutils"

mkdir -p "${tmp_dir}/bin"
cat >"${tmp_dir}/bin/brew" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "--prefix" ]; then
  shift
  if [ \$# -eq 0 ]; then
    printf '%s\n' "${brew_prefix}"
    exit 0
  fi
  printf '%s\n' "${brew_prefix}/opt/\$1"
  exit 0
fi
printf 'unexpected brew invocation: %s\n' "\$*" >&2
exit 1
EOF
chmod +x "${tmp_dir}/bin/brew"

base_path="${tmp_dir}/bin:/usr/bin:/bin"


# -----------------------------------------------------------------------------
# Test: basic invocation prepends gnubin dirs exactly once.
PATH="${base_path}"
PATH="$(cml_add_gnubins "$PATH")"
added_first="${PATH%%:*}"
case "${added_first}" in
  "${brew_prefix}/opt/gnu-sed/libexec/gnubin" \
  | "${brew_prefix}/opt/gsed/libexec/gnubin" \
  | "${brew_prefix}/opt/findutils/libexec/gnubin")
    ;;
  *)
    echo "unexpected first PATH entry: ${added_first}" >&2
    exit 1
    ;;
esac
alias_count=0
case "${PATH}" in
  *"${brew_prefix}/opt/gnu-sed/libexec/gnubin"* )
    alias_count=$((alias_count + 1))
    ;;
esac
case "${PATH}" in
  *"${brew_prefix}/opt/gsed/libexec/gnubin"* )
    alias_count=$((alias_count + 1))
    ;;
esac
if [ "${alias_count}" -ne 1 ]; then
  echo "expected exactly one gnused-style path in PATH, saw ${alias_count}" >&2
  exit 1
fi

case "${PATH}" in
  *"${brew_prefix}/opt/findutils/libexec/gnubin"* ) ;;
  *)
    echo "expected findutils gnubin in PATH" >&2
    exit 1
    ;;
esac

PATH="${orig_path}"

# -----------------------------------------------------------------------------
# Test: pre-existing alias (gsed) should not trigger duplicates.
PATH="${brew_prefix}/opt/gsed/libexec/gnubin:${base_path}"
PATH="$(cml_add_gnubins "$PATH")"

alias_count=0
case "${PATH}" in
  *"${brew_prefix}/opt/gnu-sed/libexec/gnubin"* )
    alias_count=$((alias_count + 1))
    ;;
esac
case "${PATH}" in
  *"${brew_prefix}/opt/gsed/libexec/gnubin"* )
    alias_count=$((alias_count + 1))
    ;;
esac
if [ "${alias_count}" -ne 1 ]; then
  echo "pre-existing alias produced duplicate gnused entries" >&2
  exit 1
fi

first_path_state="${PATH}"
PATH="$(cml_add_gnubins "$PATH")"
if [ "${PATH}" != "${first_path_state}" ]; then
  echo "PATH changed despite existing gnubin entries" >&2
  exit 1
fi

PATH="${orig_path}"

# -----------------------------------------------------------------------------
# Test: zsh sourcing stays idempotent and deduped.
if command -v zsh >/dev/null 2>&1; then
  # shellcheck disable=SC2016
  if ! env BREW_PREFIX="${brew_prefix}" \
           REPO_ROOT="${REPO_ROOT}" \
           TMP_BIN="${tmp_dir}/bin" \
           PATH="/usr/bin:/bin" \
           zsh -c '
set -u
PATH="${TMP_BIN}:${PATH}"
source "${REPO_ROOT}/libexec/lib/common.sh"
PATH="${BREW_PREFIX}/opt/gsed/libexec/gnubin:${PATH}"
PATH="$(cml_add_gnubins "$PATH")"
typeset -a path_entries
path_entries=(${(s.:.)PATH})
integer sed_count=0
for p in $path_entries; do
  if [[ "$p" == "${BREW_PREFIX}/opt/gnu-sed/libexec/gnubin" ]]; then
    (( sed_count++ ))
  elif [[ "$p" == "${BREW_PREFIX}/opt/gsed/libexec/gnubin" ]]; then
    (( sed_count++ ))
  fi
done
if (( sed_count != 1 )); then
  print -u2 "zsh: expected exactly one sed gnubin, saw $sed_count"
  exit 1
fi
initial_path="$PATH"
PATH="$(cml_add_gnubins "$PATH")"
if [[ "$PATH" != "$initial_path" ]]; then
  print -u2 "zsh: PATH changed after second call"
  exit 1
fi
'; then
    echo "zsh-based alias test failed" >&2
    exit 1
  fi
fi
