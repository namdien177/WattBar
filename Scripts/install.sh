#!/bin/zsh

set -euo pipefail

readonly repository="namdien177/WattBar"
readonly source_ref="${WATTBAR_REF:-main}"
readonly install_directory="${WATTBAR_INSTALL_DIR:-${HOME}/Applications}"
readonly destination_app="${install_directory}/WattBar.app"

installer_workspace=""
staged_app=""
backup_app=""

fail() {
    print -u2 -r -- "WattBar installer: $*"
    exit 1
}

cleanup() {
    local exit_code=$?

    if [[ -n "$staged_app" && -e "$staged_app" ]]; then
        /bin/rm -rf -- "$staged_app"
    fi

    if [[ -n "$backup_app" && -e "$backup_app" ]]; then
        if [[ ! -e "$destination_app" ]]; then
            /bin/mv -- "$backup_app" "$destination_app"
        else
            /bin/rm -rf -- "$backup_app"
        fi
    fi

    if [[ -n "$installer_workspace" && -d "$installer_workspace" ]]; then
        /bin/rm -rf -- "$installer_workspace"
    fi

    return "$exit_code"
}

ensure_supported_macos() {
    [[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required."

    local macos_version
    local macos_major
    macos_version="$(sw_vers -productVersion)"
    macos_major="${macos_version%%.*}"
    (( macos_major >= 14 )) || fail "macOS 14 or newer is required; found ${macos_version}."
}

ensure_developer_tools() {
    if ! /usr/bin/xcode-select -p >/dev/null 2>&1 || ! /usr/bin/xcrun --find swift >/dev/null 2>&1; then
        print -r -- "Xcode Command Line Tools are missing. Opening Apple's installer…"
        /usr/bin/xcode-select --install >/dev/null 2>&1 || true
        fail "finish the Command Line Tools installation, then run the same command again."
    fi

    local swift_version_line
    local swift_major
    swift_version_line="$(/usr/bin/xcrun swift --version 2>&1 | head -n 1)"
    swift_major="$(print -r -- "$swift_version_line" | sed -E 's/.*Apple Swift version ([0-9]+).*/\1/')"

    [[ "$swift_major" == <-> ]] || fail "could not determine the installed Swift version."
    (( swift_major >= 6 )) || fail "Swift 6 or newer is required. Update Xcode or Command Line Tools."

    command -v codesign >/dev/null 2>&1 || fail "codesign is unavailable. Reinstall Xcode Command Line Tools."
}

download_latest_source() {
    local archive_path="$installer_workspace/wattbar.tar.gz"
    local source_directory="$installer_workspace/source"

    print -r -- "Downloading ${repository}@${source_ref}…" >&2
    /usr/bin/curl \
        --proto '=https' \
        --tlsv1.2 \
        --fail \
        --location \
        --silent \
        --show-error \
        "https://github.com/${repository}/archive/refs/heads/${source_ref}.tar.gz" \
        --output "$archive_path"

    /bin/mkdir -p "$source_directory"
    /usr/bin/tar -xzf "$archive_path" -C "$source_directory" --strip-components=1
    print -r -- "$source_directory"
}

install_app() {
    local source_directory="$1"
    local built_app="$source_directory/dist/WattBar.app"

    print -r -- "Building WattBar with Swift Package Manager…"
    "$source_directory/Scripts/build-app.sh" release >/dev/null
    [[ -d "$built_app" ]] || fail "the build completed without producing WattBar.app."

    /bin/mkdir -p "$install_directory"
    staged_app="$install_directory/.WattBar.app.installing.$$"
    backup_app="$install_directory/.WattBar.app.backup.$$"

    /usr/bin/ditto "$built_app" "$staged_app"
    /usr/bin/codesign --verify --deep --strict "$staged_app"

    if [[ "${WATTBAR_SKIP_LAUNCH:-0}" != "1" ]]; then
        /usr/bin/pkill -x WattBar >/dev/null 2>&1 || true
    fi

    if [[ -e "$destination_app" ]]; then
        /bin/mv -- "$destination_app" "$backup_app"
    fi

    /bin/mv -- "$staged_app" "$destination_app"
    staged_app=""

    if [[ -e "$backup_app" ]]; then
        /bin/rm -rf -- "$backup_app"
    fi
    backup_app=""

    if [[ "${WATTBAR_SKIP_LAUNCH:-0}" != "1" ]]; then
        /usr/bin/open "$destination_app"
    fi
}

main() {
    ensure_supported_macos
    ensure_developer_tools

    installer_workspace="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/wattbar-install.XXXXXX")"
    trap cleanup EXIT INT TERM

    local source_directory
    source_directory="$(download_latest_source)"
    install_app "$source_directory"

    if [[ "${WATTBAR_SKIP_LAUNCH:-0}" == "1" ]]; then
        print -r -- "Installed: ${destination_app}"
    else
        print -r -- "Installed and launched: ${destination_app}"
    fi
    print -r -- "Temporary source and build files have been removed."
}

main "$@"
