#!/usr/bin/env bash
# Common helpers shared by cross-make-linux scripts.

# ------------------------------------------------------------
# Portable realpath helper (no external dependencies).
# ------------------------------------------------------------
_cml_realpath() {
  local target="$1"

  if command -v realpath >/dev/null 2>&1; then
    realpath "$target" 2>/dev/null && return 0
  fi

  if [ -d "$target" ]; then
    (
      cd "$target" >/dev/null 2>&1 && pwd -P
    ) || return 1
    return 0
  fi

  local dir base
  dir="$(dirname "$target")" || return 1
  base="$(basename "$target")" || return 1
  (
    cd "$dir" >/dev/null 2>&1 && printf '%s/%s\n' "$(pwd -P)" "$base"
  )
}

# ------------------------------------------------------------
# Initialise layout metadata based on caller directory.
# ------------------------------------------------------------
cml_init() {
  local caller_dir="$1"
  if [ -n "${CML_INITIALIZED:-}" ]; then
    return
  fi

  local resolved
  resolved="$(_cml_realpath "${caller_dir}")" || return 1

  CML_ROOT="$(cd "${resolved}/.." && pwd -P)"
  CML_LIBEXEC="${CML_ROOT}/libexec"
  CML_INCLUDE_DIR="${CML_LIBEXEC}/include/cross-make-linux"
  CML_LIB_DIR="${CML_LIBEXEC}/lib"
  CML_INITIALIZED=1

  # ------------------------------------------------------------
  # memoize verbosity on startup
  # ------------------------------------------------------------
  if _is_falsey "${CML_VERBOSE:-}"; then
      _CML_VERBOSE=
  else
      _CML_VERBOSE=1
  fi
  unset CML_VERBOSE
}

# ------------------------------------------------------------
# compare $1 to falsey values
# ------------------------------------------------------------
_is_falsey() {
  case "${1:-}" in
    [Ff][Aa][Ll][Ss][Ee]|[Nn][Oo]|[Oo][Ff][Ff]|0|'') return 0 ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------
# cml_debug <message>
# Prints a message to stderr only if verbose mode is enabled.
# Scripts should set _CML_VERBOSE before calling.
# ------------------------------------------------------------
cml_debug() {
  if [ -n "${_CML_VERBOSE:-}" ]; then
    printf '[CML_DBG] %b\n' "$*" >&2
  fi
}

cml_die() {
	printf '[CML_ERR] %s\n' "$*" >&2
	exit 1
}

cml_log() {
	printf '[CML_LOG] %s\n' "$*"
}

# ------------------------------------------------------------
# cml_debug_path
# Prints each element of PATH on its own line.
# ------------------------------------------------------------
cml_debug_PATH() {
  cml_debug "PATH:"
  local IFS=':'
  for element in $PATH; do
    cml_debug "  $element"
  done
}

# -----------------------------------------------------------------------------
# cml_ensure_gnu_tool <name> <expected_binary> <brew_pkg>
#
# Ensures given GNU tool (e.g. make, sed, find) is available in PATH.
# If currently resolved binary:
#   - does not exist, OR
#   - does not resolve (via realpath) to <expected_binary>,
# then the corresponding Homebrew gnubin directory for <brew_pkg> is prepended.
#
# Example:
#   ensure_gnu_tool make gmake make
#   ensure_gnu_tool sed  gsed  gnu-sed
#
# Notes:
#   - modifies PATH only if needed.
#   - pass specific tools on make command e.g.
#       cross-make-linux SED=/my/custom/sed
# -----------------------------------------------------------------------------
cml_ensure_gnu_tool() {
  local name="$1" want="$2" pkg="$3"
  local brewpath current

  if ! command -v brew >/dev/null 2>&1; then
    return 0
  fi

  brewpath="$(brew --prefix "$pkg" 2>/dev/null)" || return 0
  current="$(command -v "$name" 2>/dev/null || true)"

  local resolved_current=""
  if [ -n "$current" ]; then
    resolved_current="$(basename "$(_cml_realpath "$current")")"
  fi
  if [ -z "$current" ] || [ "$resolved_current" != "$want" ]; then
    PATH="${brewpath}/libexec/gnubin:$PATH"
  fi
}

# -----------------------------------------------------------------------------
# cml_merge_flags VAR_NAME DEFAULT_VALUE [make args...]
#
# Prepend DEFAULT_VALUE to make VAR_NAME= value honoring any existing value set
# E.g.
# cross-make-linux HOSTCFLAGS="-DFOO=BAR"
# cml_merge_flags HOSTCFLAGS "-I/path"
# -> make HOSTCFLAGS="-I/path -DFOO=BAR"
#
# Invokes make itself to determine value as seen from make.
#
# XXX Does not attempt to read command line. May promote env to command line:
#
#   HOSTCFLAGS="-DFOO=BAR" cross-make-linux ...
#       will likely become
#   cross-make-linux HOSTCFLAGS="-I/path -DFOO=BAR"
#
# -----------------------------------------------------------------------------
cml_merge_make_flags() {
  local var="$1"
  local default="$2"
  shift 2

  local existing
  existing="$(
    printf '%s\n' "print:" "	@echo \$(${var})" "%:" "	@true" |
    make -s -f - -k "$@" print 2>/dev/null || true
  )"

  if [ -n "$existing" ]; then
    printf '%s %s\n' "$default" "$existing"
  else
    printf '%s\n' "$default"
  fi
}

# -----------------------------------------------------------------------------
# cml_add_gnubins PATH
#
# usage:
#
# PATH=$(cml_add_gnubins $PATH)
#
# Prepend all $(brew --prefix)/opt/*/libexec/gnubin dirs to supplied PATH.
# Ensures paths aren't doubly inserted, including brew aliases like gsed ==
# gnu-sed
# -----------------------------------------------------------------------------
cml_add_gnubins() {
  local input_path="$1"

  if ! command -v brew >/dev/null 2>&1; then
    printf '%s\n' "$input_path"
    return 0
  fi

  local brew_prefix
  brew_prefix="$(brew --prefix 2>/dev/null)" || {
    printf '%s\n' "$input_path"
    return 0
  }
  [ -n "$brew_prefix" ] || {
    printf '%s\n' "$input_path"
    return 0
  }

  local dir real
  local to_add=""
  local seen_real=""
  local original_canonical=""

  local path_copy path_entry clean_entry
  path_copy="${input_path}:"
  while [ -n "$path_copy" ]; do
    path_entry="${path_copy%%:*}"
    path_copy="${path_copy#*:}"
    [ -n "$path_entry" ] || continue
    clean_entry="$(_cml_realpath "$path_entry" 2>/dev/null \
      || echo "$path_entry")"
    original_canonical="${original_canonical:+$original_canonical:}$clean_entry"
  done

  for dir in "$brew_prefix"/opt/*/libexec/gnubin; do
    [ -d "$dir" ] || continue
    real="$(_cml_realpath "$dir" 2>/dev/null || echo "$dir")"

    case ":$seen_real:" in
      *":$real:"*) continue ;;
    esac
    case ":$original_canonical:" in
      *":$real:"*) continue ;;
    esac

    seen_real="${seen_real:+$seen_real:}$real"
    original_canonical="${original_canonical:+$original_canonical:}$real"
    to_add="${to_add:+$to_add:}$dir"
  done

  if [ -z "$to_add" ]; then
    printf '%s\n' "$input_path"
    return 0
  fi

  if [ -n "$input_path" ]; then
    printf '%s:%s\n' "$to_add" "$input_path"
  else
    printf '%s\n' "$to_add"
  fi
}

# -----------------------------------------------------------------------------
# Write Debian md5sums file for a package directory.
# -----------------------------------------------------------------------------
cml_md5sums() {
  local pkg_dir="$1"
  local debian_dir="${pkg_dir}/DEBIAN"
  mkdir -p "${debian_dir}"

  local path rel
  find "${pkg_dir}" -path "${debian_dir}" -prune -o -type f -print0 |
    sort -z |
    while IFS= read -r -d '' path; do
      rel="${path#"${pkg_dir}"/}"
      md5sum "${path}" | sed "s|  ${path}$|  ${rel}|"
    done > "${debian_dir}/md5sums"
}


# ------------------------------------------------------------
# Return compat include directory.
# ------------------------------------------------------------
_compat_include() {
  if [ -n "${CML_INCLUDE_DIR:-}" ] && [ -d "${CML_INCLUDE_DIR}" ]; then
    printf '%s\n' "${CML_INCLUDE_DIR}"
    return
  fi

  printf '%s\n' ""
}
