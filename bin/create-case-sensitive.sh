#!/bin/bash
set -euo pipefail

# --- defaults --------------------------------------------------------------
VOL_NAME_DEFAULT=sensitive
MOUNTPOINT_DEFAULT=/Volumes/sensitive

usage() {
  cat <<EOF
Usage: case-sensitive.sh [options] [VOLUME_NAME] [MOUNTPOINT]

Create or reuse a case-sensitive APFS volume and mount it.

Defaults:
  VOLUME_NAME=${VOL_NAME_DEFAULT}
  MOUNTPOINT=${MOUNTPOINT_DEFAULT}

Options:
  -h, --help    Show this help message and exit.

Environment overrides:
  VOL_NAME      Default volume name (default: ${VOL_NAME_DEFAULT})
  MOUNTPOINT    Default mount point (default: ${MOUNTPOINT_DEFAULT})
EOF
}


# --- override by env or args ----------------------------------------------
VOL_NAME="${VOL_NAME:-$VOL_NAME_DEFAULT}"
MOUNTPOINT="${MOUNTPOINT:-$MOUNTPOINT_DEFAULT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Error: unknown option '$1'." >&2
      usage >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -gt 2 ]]; then
  echo "Error: too many positional arguments." >&2
  usage >&2
  exit 1
fi

[[ $# -ge 1 ]] && VOL_NAME="$1"
[[ $# -ge 2 ]] && MOUNTPOINT="$2"

# --- require root ----------------------------------------------------------
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Error: must run as sudo (root)." >&2
  exit 1
fi

# --- sanity: required tools ------------------------------------------------
for bin in diskutil xmllint plutil grep; do
  command -v "$bin" >/dev/null 2>&1 \
    || { echo "Error: '$bin' not found." >&2; exit 1; }
done

echo "Volume name:    $VOL_NAME"
echo "Mountpoint:     $MOUNTPOINT"

# --- detect APFS container via plist + plutil ------------------------------
container=$(
  diskutil info -plist /System/Volumes/Data \
    | plutil -extract APFSContainerReference raw -o - - 2>/dev/null \
    || true
)
if [[ -z "$container" ]]; then
  echo "Error: could not detect APFS container." >&2
  exit 1
fi
echo "Using APFS container: $container"

# --- create APFS (case-sensitive) volume if not present --------------------
if ! diskutil apfs list -plist \
  | xmllint --xpath \
      "boolean(//key[text()='Name']/following-sibling::*[1]"\
      "[text()='${VOL_NAME}'])" - 2>/dev/null || true; then
  echo "Creating APFSX volume '${VOL_NAME}'..."
  create_out="$(
    diskutil apfs addVolume "$container" APFSX "$VOL_NAME" || true
  )"
else
  echo "APFS volume '${VOL_NAME}' already exists; reusing."
  create_out=""
fi

# --- resolve device identifier (poll up to 5s) -----------------------------
dev=""
for i in {1..10}; do
  dev=$(
    diskutil apfs list -plist "$container" \
      | xmllint --xpath \
        "string(//dict[key='Name' and \
string(./following-sibling::*[1])='${VOL_NAME}']\
/following-sibling::dict/key[text()='DeviceIdentifier']\
/following-sibling::*[1])" - 2>/dev/null || true
  )
  [[ -n "$dev" ]] && break
  sleep 0.5
done

# --- fallback: parse from addVolume output or mounted info -----------------
if [[ -z "$dev" && -n "$create_out" ]]; then
  dev="$(printf '%s\n' "$create_out" \
    | grep -Eo 'disk[0-9]+s[0-9]+' | tail -1 || true)"
fi
if [[ -z "$dev" && -d "$MOUNTPOINT" ]]; then
  dev="$(
    diskutil info -plist "$MOUNTPOINT" \
      | plutil -extract DeviceIdentifier raw -o - - 2>/dev/null \
      || true
  )"
fi

if [[ -z "$dev" ]]; then
  echo "Error: could not determine device node for '${VOL_NAME}'." >&2
  exit 1
fi
echo "Volume device: /dev/$dev"

# --- prepare mountpoint ----------------------------------------------------
if mount | grep -q "on ${MOUNTPOINT} "; then
  echo "${MOUNTPOINT} is already a mountpoint. Nothing to do."
  exit 0
fi

if [[ -e "$MOUNTPOINT" ]]; then
  if [[ -n "$(ls -A "$MOUNTPOINT" 2>/dev/null || true)" ]]; then
    echo "Error: ${MOUNTPOINT} exists and is not empty." >&2
    exit 1
  fi
else
  mkdir -p "$MOUNTPOINT"
fi

# --- ensure device not mounted elsewhere, then mount -----------------------
if diskutil info -plist "/dev/$dev" \
  | plutil -extract Mounted raw -o - - 2>/dev/null \
  | grep -q "^Yes$"; then
  diskutil unmount "/dev/$dev" >/dev/null || true
fi

echo "Mounting /dev/$dev at ${MOUNTPOINT} ..."
diskutil mount -mountPoint "$MOUNTPOINT" "/dev/$dev"

echo "✅ '${VOL_NAME}' mounted at ${MOUNTPOINT}"
