#!/usr/bin/env bash
# Install, update, or remove Fastfetch from its official Linux releases.
set -euo pipefail

readonly SCRIPT_NAME=${0##*/}
readonly API_BASE="https://api.github.com/repos/fastfetch-cli/fastfetch/releases"

ACTION="install"
PREFIX=""
RELEASE="latest"
FORCE=0
USE_PACKAGE_MANAGER=0
PURGE_CONFIG=0
PACKAGE_MANAGER=""
MANIFEST=""
TMPDIR_INSTALLER=""

declare -a MANIFEST_PATHS=()
declare -a MANIFEST_HASHES=()
MANIFEST_METHOD=""
MANIFEST_VERSION=""
MANIFEST_PREFIX=""
MANIFEST_MANAGER=""
MANIFEST_PACKAGE=""

die() {
    printf '%s: %s\n' "$SCRIPT_NAME" "$*" >&2
    exit 1
}

info() {
    printf '%s\n' "$*"
}

cleanup() {
    [[ -n "$TMPDIR_INSTALLER" && -d "$TMPDIR_INSTALLER" ]] && rm -rf -- "$TMPDIR_INSTALLER"
    return 0
}
trap cleanup EXIT

usage() {
    cat <<'EOF'
Usage: install-fastfetch.sh [install|update|uninstall] [options]

Commands:
  install                 Install Fastfetch (default).
  update                  Update an installer-managed installation.
  uninstall               Remove an installer-managed installation.

Options:
  --prefix DIR            Install under DIR (default: /usr/local as root,
                          otherwise ~/.local).
  --release VERSION       Install a specific release, such as 2.67.0.
  --package-manager       Use the detected package manager instead of an
                          official release archive.
  --force                 Reinstall the selected release during update.
  --purge-config          With uninstall, also remove ~/.config/fastfetch.
  -h, --help              Show this help text.

Official release archives are preferred. A package manager is used only when
explicitly requested or when no compatible official archive exists.
EOF
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

run_as_root() {
    if (( EUID == 0 )); then
        "$@"
    elif command_exists sudo; then
        sudo "$@"
    else
        die "installing prerequisites requires root privileges; rerun as root or install sudo"
    fi
}

detect_package_manager() {
    local candidate
    for candidate in apt-get dnf yum pacman zypper apk xbps-install; do
        if command_exists "$candidate"; then
            PACKAGE_MANAGER=$candidate
            return
        fi
    done
}

install_system_packages() {
    local -a packages=("$@")
    detect_package_manager
    [[ -n "$PACKAGE_MANAGER" ]] || die "missing required tools (${packages[*]}) and no supported package manager was found"

    info "Installing missing prerequisites: ${packages[*]}"
    case "$PACKAGE_MANAGER" in
        apt-get)
            run_as_root env DEBIAN_FRONTEND=noninteractive apt-get update
            run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
            ;;
        dnf)
            run_as_root dnf install -y "${packages[@]}"
            ;;
        yum)
            run_as_root yum install -y "${packages[@]}"
            ;;
        pacman)
            run_as_root pacman -S --needed --noconfirm "${packages[@]}"
            ;;
        zypper)
            run_as_root zypper --non-interactive install "${packages[@]}"
            ;;
        apk)
            run_as_root apk add "${packages[@]}"
            ;;
        xbps-install)
            run_as_root xbps-install -y "${packages[@]}"
            ;;
    esac
}

install_prerequisites() {
    local -a packages=()

    command_exists tar || packages+=(tar)
    command_exists jq || packages+=(jq)
    command_exists sha256sum || packages+=(coreutils)
    command_exists install || packages+=(coreutils)
    command_exists mktemp || packages+=(coreutils)
    if ! command_exists curl && ! command_exists wget; then
        packages+=(curl)
    fi

    (( ${#packages[@]} == 0 )) && return
    install_system_packages "${packages[@]}"
}

ensure_checksum_tool() {
    command_exists sha256sum || install_system_packages coreutils
}

download() {
    local url=$1 destination=$2
    if command_exists curl; then
        curl --fail --location --proto '=https' --tlsv1.2 --connect-timeout 15 \
            --retry 3 --retry-delay 1 --retry-connrefused --output "$destination" "$url"
    elif command_exists wget; then
        wget --https-only --timeout=15 --tries=3 --output-document="$destination" "$url"
    else
        die "curl or wget is required to download Fastfetch"
    fi
}

detect_prefix() {
    if [[ -z "$PREFIX" ]]; then
        if (( EUID == 0 )); then
            PREFIX=/usr/local
        else
            PREFIX="${HOME:?HOME is not set}/.local"
        fi
    fi
    PREFIX=${PREFIX%/}
    [[ -n "$PREFIX" && "$PREFIX" == /* ]] || die "--prefix must be an absolute path"
    MANIFEST="$PREFIX/share/fastfetch-installer/manifest"
}

detect_platform() {
    [[ $(uname -s) == "Linux" ]] || die "this installer supports Linux only"
}

detect_libc() {
    if command_exists getconf && getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
        printf '%s\n' glibc
    elif command_exists ldd && ldd --version 2>&1 | grep -qi musl; then
        printf '%s\n' musl
    else
        printf '%s\n' unknown
    fi
}

map_architecture() {
    case "$(uname -m)" in
        x86_64|amd64) printf '%s\n' amd64 ;;
        aarch64|arm64) printf '%s\n' aarch64 ;;
        armv7l|armv7) printf '%s\n' armv7l ;;
        i386|i486|i586|i686) printf '%s\n' i686 ;;
        loongarch64) printf '%s\n' loongarch64 ;;
        ppc64le) printf '%s\n' ppc64le ;;
        riscv64) printf '%s\n' riscv64 ;;
        s390x) printf '%s\n' s390x ;;
        *) return 1 ;;
    esac
}

release_metadata() {
    local endpoint=$1
    TMPDIR_INSTALLER=$(mktemp -d "${TMPDIR:-/tmp}/fastfetch-installer.XXXXXXXX")
    chmod 700 "$TMPDIR_INSTALLER"
    download "$API_BASE/$endpoint" "$TMPDIR_INSTALLER/release.json" || die "could not download release metadata; check network access, proxy settings, and GitHub API limits"
}

fetch_archive() {
    local arch libc asset tag digest url computed extracted
    local -a extracted_candidates
    detect_platform
    install_prerequisites
    arch=$(map_architecture) || return 2
    libc=$(detect_libc)

    if [[ "$RELEASE" == "latest" ]]; then
        release_metadata latest
    else
        RELEASE=${RELEASE#v}
        [[ "$RELEASE" =~ ^[0-9A-Za-z._-]+$ ]] || die "invalid release version: $RELEASE"
        release_metadata "tags/v$RELEASE"
    fi

    tag=$(jq -er '.tag_name' "$TMPDIR_INSTALLER/release.json") || die "GitHub returned invalid release metadata (possibly an API rate limit)"
    RELEASE=${tag#v}

    case "$libc:$arch" in
        musl:amd64) asset="fastfetch-musl-amd64.tar.gz" ;;
        glibc:*|unknown:*) asset="fastfetch-linux-$arch.tar.gz" ;;
        *) return 2 ;;
    esac

    url=$(jq -er --arg name "$asset" '.assets[] | select(.name == $name) | .browser_download_url' "$TMPDIR_INSTALLER/release.json") || return 2
    digest=$(jq -er --arg name "$asset" '.assets[] | select(.name == $name) | .digest' "$TMPDIR_INSTALLER/release.json") || die "release metadata has no SHA-256 digest for $asset"
    digest=${digest#sha256:}
    [[ "$digest" =~ ^[0-9a-fA-F]{64}$ ]] || die "release metadata has an invalid SHA-256 digest for $asset"

    info "Downloading Fastfetch $RELEASE ($asset)"
    download "$url" "$TMPDIR_INSTALLER/$asset" || die "could not download $asset; check network access, proxy settings, and GitHub availability"
    computed=$(sha256sum "$TMPDIR_INSTALLER/$asset" | awk '{print $1}')
    [[ "$computed" == "$digest" ]] || die "SHA-256 verification failed for $asset"

    mkdir "$TMPDIR_INSTALLER/extract"
    tar -xzf "$TMPDIR_INSTALLER/$asset" -C "$TMPDIR_INSTALLER/extract" || die "could not extract $asset"
    extracted_candidates=("$TMPDIR_INSTALLER"/extract/*/usr/bin/fastfetch)
    extracted=${extracted_candidates[0]}
    [[ -x "$extracted" ]] || die "official archive does not contain usr/bin/fastfetch"
    "$extracted" --version >/dev/null || die "staged Fastfetch failed its version check"

    STAGED_BINARY=$extracted
    STAGED_SHA256=$(sha256sum "$extracted" | awk '{print $1}')
    STAGED_ASSET=$asset
}

write_manifest() {
    local destination=$1 method=$2 version=$3 prefix=$4 path=$5 hash=$6
    local manager=${7:-} package=${8:-}
    {
        printf 'format=1\n'
        printf 'method=%s\n' "$method"
        printf 'version=%s\n' "$version"
        printf 'prefix=%s\n' "$prefix"
        [[ -n "$manager" ]] && printf 'manager=%s\n' "$manager"
        [[ -n "$package" ]] && printf 'package=%s\n' "$package"
        printf 'file=%s|%s\n' "$path" "$hash"
    } > "$destination"
}

install_archive() {
    local binary="$PREFIX/bin/fastfetch"
    local manifest_dir="$PREFIX/share/fastfetch-installer"
    local new_binary new_manifest

    [[ ! -e "$binary" ]] || die "$binary already exists and is not safe to overwrite"
    mkdir -p "$PREFIX/bin" "$manifest_dir"
    new_binary="$PREFIX/bin/.fastfetch.new.$$"
    new_manifest="$manifest_dir/.manifest.new.$$"
    install -m 0755 "$STAGED_BINARY" "$new_binary"
    write_manifest "$new_manifest" archive "$RELEASE" "$PREFIX" "$binary" "$STAGED_SHA256"
    mv -f "$new_binary" "$binary"
    mv -f "$new_manifest" "$MANIFEST"
    info "Installed Fastfetch $RELEASE to $binary"
}

load_manifest() {
    local line key value path hash format=""
    [[ -f "$MANIFEST" ]] || die "no installer manifest at $MANIFEST"
    MANIFEST_PATHS=()
    MANIFEST_HASHES=()
    MANIFEST_METHOD=""
    MANIFEST_VERSION=""
    MANIFEST_PREFIX=""
    MANIFEST_MANAGER=""
    MANIFEST_PACKAGE=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == *=* ]] || die "invalid installer manifest"
        key=${line%%=*}
        value=${line#*=}
        case "$key" in
            format) format=$value ;;
            method) MANIFEST_METHOD=$value ;;
            version) MANIFEST_VERSION=$value ;;
            prefix) MANIFEST_PREFIX=$value ;;
            manager) MANIFEST_MANAGER=$value ;;
            package) MANIFEST_PACKAGE=$value ;;
            file)
                path=${value%%|*}
                hash=${value#*|}
                [[ "$path" != "$value" && "$hash" =~ ^[0-9a-fA-F]{64}$ ]] || die "invalid file entry in installer manifest"
                MANIFEST_PATHS+=("$path")
                MANIFEST_HASHES+=("$hash")
                ;;
            *) die "unknown field in installer manifest: $key" ;;
        esac
    done < "$MANIFEST"

    [[ "$format" == "1" && "$MANIFEST_METHOD" =~ ^(archive|package)$ && -n "$MANIFEST_VERSION" && "$MANIFEST_PREFIX" == "$PREFIX" && ${#MANIFEST_PATHS[@]} -gt 0 ]] || die "invalid installer manifest"
    if [[ "$MANIFEST_METHOD" == package ]]; then
        [[ -n "$MANIFEST_MANAGER" && -n "$MANIFEST_PACKAGE" ]] || die "invalid package-manager manifest"
    fi
}

verify_managed_files() {
    local index path actual
    for index in "${!MANIFEST_PATHS[@]}"; do
        path=${MANIFEST_PATHS[index]}
        [[ -f "$path" ]] || die "managed file is missing: $path"
        actual=$(sha256sum "$path" | awk '{print $1}')
        [[ "$actual" == "${MANIFEST_HASHES[index]}" ]] || die "managed file was modified and will not be replaced or removed: $path"
    done
}

version_is_newer() {
    local candidate=$1 current=$2 newest
    newest=$(printf '%s\n%s\n' "$candidate" "$current" | sort -V | tail -n 1)
    [[ "$newest" == "$candidate" && "$candidate" != "$current" ]]
}

package_owned_binary() {
    local candidate
    case "$PACKAGE_MANAGER" in
        apt-get)
            candidate=$(dpkg-query -L fastfetch 2>/dev/null | awk '/\/bin\/fastfetch$/ { print; exit }')
            ;;
        dnf|yum|zypper)
            candidate=$(rpm -ql fastfetch 2>/dev/null | awk '/\/bin\/fastfetch$/ { print; exit }')
            ;;
        pacman)
            candidate=$(pacman -Ql fastfetch 2>/dev/null | awk '$2 ~ /\/bin\/fastfetch$/ { print $2; exit }')
            ;;
        apk)
            candidate=$(apk info -L fastfetch 2>/dev/null | awk '/(^|\/)usr\/bin\/fastfetch$/ { print "/" $0; exit }')
            ;;
        xbps-install)
            candidate=$(xbps-query -f fastfetch 2>/dev/null | awk '/\/bin\/fastfetch$/ { print; exit }')
            ;;
    esac
    [[ -n "${candidate:-}" && -x "$candidate" ]] || return 1
    printf '%s\n' "$candidate"
}

install_package() {
    local binary version hash
    [[ "$RELEASE" == latest ]] || die "--release is only supported with official release archives"
    detect_package_manager
    [[ -n "$PACKAGE_MANAGER" ]] || die "no supported package manager was found"

    info "Installing Fastfetch with $PACKAGE_MANAGER"
    case "$PACKAGE_MANAGER" in
        apt-get) run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y fastfetch ;;
        dnf) run_as_root dnf install -y fastfetch ;;
        yum) run_as_root yum install -y fastfetch ;;
        pacman) run_as_root pacman -S --needed --noconfirm fastfetch ;;
        zypper) run_as_root zypper --non-interactive install fastfetch ;;
        apk) run_as_root apk add fastfetch ;;
        xbps-install) run_as_root xbps-install -y fastfetch ;;
    esac

    binary=$(package_owned_binary) || die "could not locate the Fastfetch binary owned by $PACKAGE_MANAGER"
    version=$(fastfetch --version | awk 'NR == 1 { print $2 }')
    [[ -n "$version" ]] || die "could not determine the package-installed Fastfetch version"
    hash=$(sha256sum "$binary" | awk '{print $1}')
    mkdir -p "$(dirname "$MANIFEST")"
    write_manifest "$MANIFEST" package "$version" "$PREFIX" "$binary" "$hash" "$PACKAGE_MANAGER" fastfetch
    info "Installed Fastfetch $version with $PACKAGE_MANAGER"
}

remove_package() {
    case "$MANIFEST_MANAGER" in
        apt-get) run_as_root env DEBIAN_FRONTEND=noninteractive apt-get remove -y "$MANIFEST_PACKAGE" ;;
        dnf) run_as_root dnf remove -y "$MANIFEST_PACKAGE" ;;
        yum) run_as_root yum remove -y "$MANIFEST_PACKAGE" ;;
        pacman) run_as_root pacman -Rns --noconfirm "$MANIFEST_PACKAGE" ;;
        zypper) run_as_root zypper --non-interactive remove "$MANIFEST_PACKAGE" ;;
        apk) run_as_root apk del "$MANIFEST_PACKAGE" ;;
        xbps-install) run_as_root xbps-remove -R "$MANIFEST_PACKAGE" ;;
        *) die "unsupported package manager recorded in manifest: $MANIFEST_MANAGER" ;;
    esac
}

install_command() {
    detect_prefix
    [[ ! -f "$MANIFEST" ]] || die "Fastfetch is already installer-managed; use update or uninstall"
    if (( USE_PACKAGE_MANAGER )); then
        install_package
        return
    fi
    if fetch_archive; then
        install_archive
    else
        info "No compatible official archive is available; falling back to the package manager."
        install_package
    fi
}

update_command() {
    local current
    detect_prefix
    load_manifest
    ensure_checksum_tool
    verify_managed_files

    if [[ "$MANIFEST_METHOD" == package ]]; then
        info "Updating Fastfetch with $MANIFEST_MANAGER"
        install_package
        return
    fi

    install_prerequisites
    current=$MANIFEST_VERSION
    fetch_archive || die "no compatible official archive is available for this system"
    if (( ! FORCE )) && ! version_is_newer "$RELEASE" "$current"; then
        info "Fastfetch $current is already current or newer."
        return
    fi

    # Create replacements beside their targets so each rename is atomic.
    local binary="${MANIFEST_PATHS[0]}"
    local manifest_dir
    manifest_dir=$(dirname "$MANIFEST")
    local new_binary="$(dirname "$binary")/.fastfetch.new.$$"
    local new_manifest="$manifest_dir/.manifest.new.$$"
    install -m 0755 "$STAGED_BINARY" "$new_binary"
    write_manifest "$new_manifest" archive "$RELEASE" "$PREFIX" "$binary" "$STAGED_SHA256"
    mv -f "$new_binary" "$binary"
    mv -f "$new_manifest" "$MANIFEST"
    info "Updated Fastfetch $current to $RELEASE"
}

uninstall_command() {
    local index path config_dir
    detect_prefix
    load_manifest
    ensure_checksum_tool
    verify_managed_files

    if [[ "$MANIFEST_METHOD" == package ]]; then
        remove_package
    else
        for index in "${!MANIFEST_PATHS[@]}"; do
            path=${MANIFEST_PATHS[index]}
            rm -f -- "$path"
        done
    fi
    rm -f -- "$MANIFEST"
    rmdir "$(dirname "$MANIFEST")" 2>/dev/null || true
    rmdir "$PREFIX/share" 2>/dev/null || true

    if (( PURGE_CONFIG )); then
        config_dir="${XDG_CONFIG_HOME:-${HOME:?HOME is not set}/.config}/fastfetch"
        rm -rf -- "$config_dir"
        info "Removed $config_dir"
    fi
    info "Removed installer-managed Fastfetch"
}

parse_arguments() {
    case "${1:-}" in
        install|update|uninstall)
            ACTION=$1
            shift
            ;;
    esac

    while (( $# > 0 )); do
        case "$1" in
            --prefix)
                (( $# >= 2 )) || die "--prefix requires a directory"
                PREFIX=$2
                shift 2
                ;;
            --release)
                (( $# >= 2 )) || die "--release requires a version"
                RELEASE=$2
                shift 2
                ;;
            --package-manager)
                USE_PACKAGE_MANAGER=1
                shift
                ;;
            --force)
                FORCE=1
                shift
                ;;
            --purge-config)
                PURGE_CONFIG=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *) die "unknown argument: $1" ;;
        esac
    done

    [[ "$ACTION" == uninstall || $PURGE_CONFIG -eq 0 ]] || die "--purge-config is only valid with uninstall"
    [[ "$ACTION" != uninstall || $USE_PACKAGE_MANAGER -eq 0 ]] || die "--package-manager is not valid with uninstall"
    [[ "$ACTION" != update || $USE_PACKAGE_MANAGER -eq 0 ]] || die "--package-manager is not valid with update"
}

main() {
    parse_arguments "$@"
    case "$ACTION" in
        install) install_command ;;
        update) update_command ;;
        uninstall) uninstall_command ;;
    esac
}

main "$@"
