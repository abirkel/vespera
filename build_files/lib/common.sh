#!/usr/bin/bash
# Shared helpers. Sourced by every numbered script.
# shellcheck shell=bash

# Fail early; trace in CI.
set -Eeuo pipefail
if [[ "${CI:-}" == "true" || "${SET_X:-0}" == "1" ]]; then set -x; fi

readonly CTX="${CTX:-/ctx}"
readonly SYSTEM_FILES="${CTX}/system_files"
readonly AKMODS_RPMS="${AKMODS_RPMS:-/tmp/akmods-rpms}"

# Printed as a summary at the end so soft failures cannot be missed. Each numbered
# script sources this in its own shell, so create — never truncate — here.
WARNINGS_FILE="/tmp/vespera-build-warnings"
[[ -e "${WARNINGS_FILE}" ]] || : >"${WARNINGS_FILE}"

log()   { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
info()  { printf '    %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; printf '%s\n' "$*" >>"${WARNINGS_FILE}"; }
die()   { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

# Collapses each script in the CI log.
group_start() { [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::group::$*" || log "$*"; }
group_end()   { [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::endgroup::" || true; }

# The kernel this image boots. Every kmod must match it exactly.
kernel_version() { rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core; }

# Read from the base image, not hardcoded — this is what lets BASE_TAG follow
# ublue's rolling `latest` across a Fedora release with no edit here. The Terra GPG
# key filename and cicpoffs asset name both embed it, so a hardcoded 44 would reach
# for RPM-GPG-KEY-terra44 on an F45 base.
fedora_version() { rpm -E %fedora; }

# retry <attempts> <delay> <command...>
retry() {
    local -i attempts="$1" delay="$2" n=1
    shift 2
    until "$@"; do
        if (( n >= attempts )); then
            warn "command failed after ${attempts} attempts: $*"
            return 1
        fi
        info "attempt ${n}/${attempts} failed; retrying in ${delay}s"
        sleep "${delay}"
        n=$(( n + 1 ))
    done
}

# Fail on HTTP error, retry, follow redirects.
fetch() { retry 5 5 curl --fail --silent --show-error --location --retry 3 "$@"; }

# copr_install <owner/project> <pkg>...
# Repo enabled for exactly one transaction, then left disabled (Aurora's pattern), so
# a broken or malicious COPR cannot shadow a Fedora package outside its own install.
copr_install() {
    local copr="$1"; shift
    (( $# )) || die "copr_install: no packages given for ${copr}"
    local repo_id="copr:copr.fedorainfracloud.org:${copr//\//:}"
    info "COPR ${copr}: $*"
    dnf5 -y copr enable "${copr}"
    dnf5 -y copr disable "${copr}"
    dnf5 -y install --enablerepo="${repo_id}" "$@"
}

# repo_install <repo-glob> <pkg>...   Same idea for negativo17 and Terra.
repo_install() {
    local repo="$1"; shift
    (( $# )) || die "repo_install: no packages given for ${repo}"
    info "repo ${repo}: $*"
    dnf5 -y install --enable-repo="${repo}" "$@"
}

# sync_files [subdir]   Copy system_files/ into the image, preserving symlinks.
sync_files() {
    local sub="${1:-}"
    local src="${SYSTEM_FILES}${sub:+/$sub}"
    [[ -d "$src" ]] || die "sync_files: ${src} does not exist"
    rsync -aK --chown=root:root "${src}/" /
}
