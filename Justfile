# Vespera — developer entry points.
#
# The REPO justfile, run on a workstation. Unrelated to the in-image ujust recipes in
# system_files/usr/share/ublue-os/just/60-custom.just.
#
# Kept compatible with just 1.21 (Ubuntu 24.04's, which is what CI installs from apt),
# so no `[group(...)]` attributes — they need >= 1.27, and pinning a newer just in CI is
# more supply-chain surface than a tidier `--list` is worth.

set shell := ["bash", "-euo", "pipefail", "-c"]

image_name  := env("IMAGE_NAME", "vespera")
image_vendor := env("IMAGE_VENDOR", "abirkel")
image_registry := env("IMAGE_REGISTRY", "ghcr.io/abirkel")
default_tag := env("DEFAULT_TAG", "latest")
bib_image := env("BIB_IMAGE", "ghcr.io/osbuild/bootc-image-builder:latest")

[private]
default:
    @just --list --unsorted

# ---------------------------------------------------------------------------
# Static checks. The workflow runs `just check` first, so a syntax error costs seconds
# instead of a 30-minute image build.
# ---------------------------------------------------------------------------

# Run every static check (syntax, shell, yaml, json, structure)
check: check-just check-sh check-yaml check-json check-layout
    @echo "all checks passed"

# Validate this justfile and the in-image ujust recipes parse.
# Parse-only: `--fmt --check` reflows the section-header comments this file relies on.
check-just:
    @just --justfile Justfile --summary >/dev/null && echo "Justfile parses"
    @# 60-custom.just is imported, not standalone, so parse it behind a wrapper.
    @tmp=$(mktemp -d); \
      cp system_files/usr/share/ublue-os/just/60-custom.just "$tmp/60-custom.just"; \
      printf 'import "60-custom.just"\n' > "$tmp/Justfile"; \
      just --justfile "$tmp/Justfile" --summary >/dev/null; \
      rm -rf "$tmp"; \
      echo "60-custom.just parses"

# shellcheck every build script and shipped shell file
check-sh:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v shellcheck >/dev/null; then
        echo "shellcheck not installed; skipping" >&2
        exit 0
    fi
    # Discovered, not hardcoded: shipped scripts have no consistent extension
    # (system-sleep hooks and libexec helpers have none), so match on the shebang.
    mapfile -t files < <(
        find build_files -name '*.sh'
        find system_files -type f -exec grep -lE '^#!.*(bash|/bin/sh)' {} +
    )
    # -x: follow `source` into lib/common.sh
    # SC1091: sourced paths only resolve inside the container
    shellcheck -x -e SC1091 -S warning "${files[@]}"
    echo "shellcheck clean (${#files[@]} files)"

# Validate the workflow YAML
check-yaml:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v yamllint >/dev/null; then
        yamllint -d '{extends: default, rules: {line-length: {max: 100}, truthy: {check-keys: false}, comments: {min-spaces-from-content: 1}}}' \
            .github/workflows/
    elif python3 -c 'import yaml' 2>/dev/null; then
        for f in .github/workflows/*.yml; do
            python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$f"
            echo "parsed $f"
        done
    elif command -v npx >/dev/null; then
        # `yaml`'s CLI reads from stdin and exits non-zero on a parse error.
        for f in .github/workflows/*.yml; do
            npx --yes yaml <"$f" >/dev/null
            echo "parsed $f"
        done
    else
        # Deliberately loud. CI has yamllint preinstalled and takes the first branch, so a
        # local run that silently skips can pass while CI fails — which is exactly what
        # happened once with a 182-character line that only yamllint's line-length rule
        # catches. Install yamllint locally to check what CI will actually check.
        echo "WARNING: no YAML linter found. CI uses yamllint and checks line length," >&2
        echo "         which the fallbacks above do NOT. Install yamllint to match CI." >&2
    fi

# Validate the renovate config and the bootc-image-builder TOMLs
check-json:
    #!/usr/bin/env bash
    set -euo pipefail
    # json5 needs a real parser; node is the only one commonly present.
    if command -v npx >/dev/null; then
        npx --yes json5 -c .github/renovate.json5 >/dev/null && echo "renovate.json5 parses"
    else
        echo "npx unavailable; skipping renovate.json5 parse" >&2
    fi
    if command -v python3 >/dev/null; then
        python3 -c 'import glob,tomllib;[print("parsed",f) for f in sorted(glob.glob("disk_config/*.toml")) if tomllib.load(open(f,"rb")) is None or True]'
    fi

# Assert repo invariants that are easy to break silently
check-layout:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    note() { echo "  FAIL: $*" >&2; fail=1; }

    # build.sh's `bash $script` masks a missing +x locally, but git records it wrong.
    while IFS= read -r f; do
        [[ -x "$f" ]] || note "$f is not executable (git update-index --chmod=+x)"
    done < <(find build_files -name '*.sh')

    # The shipped ublue justfile is package-owned and hooked via the `import?` line it
    # already has. Appending to it — Bazzite's and old vespera's approach — breaks on
    # every ublue-os-just update. Match only *writes*, so the rpm -V guard and the parse
    # check are not false positives.
    if grep -rnE '(sed +-i|tee|>>?[[:space:]]*)[^|]*/usr/share/ublue-os/justfile' build_files/ \
         | grep -vE 'rpm -V|--justfile' ; then
        note "build_files/ writes to /usr/share/ublue-os/justfile — use 60-custom.just"
    fi

    # Branding must stay stock: nothing may ship an os-release or a distro logo.
    while IFS= read -r f; do
        note "branding file must not be shipped: $f"
    done < <(find system_files \( -name 'os-release' -o -name 'kcm-about-distrorc' \) -o -path '*plymouth*' -type f)

    # 85-signing.sh dies on a placeholder key; catch it here, not 20 minutes in.
    if grep -qi placeholder cosign.pub; then
        echo "  WARN: cosign.pub is still a placeholder; 'just build' will fail" >&2
    fi

    # kargs belong in the image, not in disk_config.
    grep -q 'append = ""' disk_config/disk.toml \
        || note "disk.toml sets kernel args; they belong in usr/lib/bootc/kargs.d"

    # rsync -aK copies empty directories too.
    while IFS= read -r d; do
        note "empty directory in system_files (will be synced into the image): $d"
    done < <(find system_files -type d -empty)

    # Nothing may overwrite a package-owned Qt logging config; the override
    # belongs in /etc/xdg/QtProject/ (see that file's header).
    if [[ -e system_files/usr/share/qt5/qtlogging.ini || -e system_files/usr/share/qt6/qtlogging.ini ]]; then
        note "system_files ships /usr/share/qt{5,6}/qtlogging.ini, which is owned by qt{5,6}-qtbase; use /etc/xdg/QtProject/qtlogging.ini"
    fi

    # Every shipped config must say where it came from, so a yearly audit knows what to
    # diff against. See any file in system_files/ for the format.
    while IFS= read -r f; do
        grep -q 'PROVENANCE:' "$f" || note "no PROVENANCE header: $f"
    done < <(find system_files -type f)

    # Renovate refuses to run with more than one config file. Some editors auto-generate
    # a minified renovate.json beside the .json5, so what matters is whether it is
    # *committed*.
    [[ -f .github/renovate.json5 ]] || note ".github/renovate.json5 is missing"
    if git rev-parse --git-dir >/dev/null 2>&1; then
        if git ls-files --error-unmatch .github/renovate.json >/dev/null 2>&1; then
            note ".github/renovate.json is tracked; Renovate fails with two config files (it is .gitignore'd for a reason)"
        fi
    elif [[ -f .github/renovate.json ]]; then
        echo "  WARN: .github/renovate.json exists (editor artifact); it is .gitignore'd" >&2
    fi

    (( fail == 0 )) && echo "layout ok"
    exit $fail

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

# Build the image locally (podman). Slow; needs ~40 GB free.
build tag=default_tag:
    podman build \
        --tag "{{ image_name }}:{{ tag }}" \
        --build-arg "IMAGE_NAME={{ image_name }}" \
        --build-arg "IMAGE_VENDOR={{ image_vendor }}" \
        --build-arg "IMAGE_REGISTRY={{ image_registry }}" \
        --build-arg "VERSION_TAG=local-$(date -u +%Y%m%d%H%M)" \
        --file Containerfile \
        .

# Build without the slow optional extras (MS fonts, yeetmouse kmod)
build-fast tag="fast":
    podman build \
        --tag "{{ image_name }}:{{ tag }}" \
        --build-arg "IMAGE_NAME={{ image_name }}" \
        --build-arg "IMAGE_VENDOR={{ image_vendor }}" \
        --build-arg "IMAGE_REGISTRY={{ image_registry }}" \
        --build-arg "ENABLE_MSFONTS=0" \
        --build-arg "ENABLE_YEETMOUSE=0" \
        --file Containerfile \
        .

# Rechunk a built image so updates download deltas instead of the whole thing.
#
# WHY IT MATTERS: the Containerfile does one big RUN on top of the base's ~259
# well-chunked layers, so everything added — Steam, Wine (1.3 GiB alone), the virt
# stack, fonts — lands in a SINGLE layer whose digest changes whenever any of it does.
# A one-package update then re-downloads all of it. Rechunking re-splits the flattened
# tree into per-package content-addressed layers, so only changed packages move.
#
# TOOL CHOICE: `rpm-ostree compose build-chunked-oci` — in-tree, already present in
# the base image (rpm-ostree 2026.2, nothing to install), and what both Bazzite and
# ublue's own image-template use.
#
# NOT coreos/chunkah, even though chunkah is by the same upstream (the coreos org),
# is packaged in Fedora 44, and describes itself as "a generalized successor to
# rpm-ostree's build-chunked-oci". The blocker is specific, and it is chunkah's own
# README saying it: "chunkah has no special handling for bootable container images
# ... Packing still needs to be fine-tuned for bootable images". Worse for us, our
# base is the OSTree flavour of bootc image (it carries ostree.commit /
# ostree.final-diffid / rpmostree.inputhash), and chunkah handles that only by
# converting it to a "plain" image: `--prune /sysroot/`, strip the ostree labels,
# re-add containers.bootc=1 by hand. That is a semantic change to the image, not a
# repacking. Revisit when that caveat leaves chunkah's README.
#
# NOT hhd-dev/rechunk either: a third-party action needing rootful podman and a
# pinned runner, for the same core benefit.
#
# The trick, from ublue's image-template: run rpm-ostree FROM THE IMAGE ITSELF with the
# image mounted as a rootfs, so nothing extra is needed on the runner.
#
# LABELS ARE NOT INHERITED. Building from a bare rootfs regenerates the OCI config, so
# every org.opencontainers.image.* label must be passed back in explicitly.
rechunk tag=default_tag $max_layers="127":
    #!/usr/bin/env bash
    set -euo pipefail

    img="localhost/{{ image_name }}:{{ tag }}"
    podman image exists "$img" || { echo "no such image: $img (run 'just build' first)" >&2; exit 1; }

    # Preserve the labels the build set, so the rechunked image is not anonymous.
    mapfile -t label_args < <(
        podman inspect "$img" \
          | jq -r '.[0].Config.Labels // {} | to_entries[] | "--label\n\(.key)=\(.value)"'
    )

    # Pins the layer PLAN against the last published image, so unchanged packages stay
    # in identically-hashed layers instead of being reshuffled by the grouping
    # algorithm. Without it, two builds of the same content can land on different
    # boundaries and clients re-download everything anyway. Only the remote manifest is
    # read — no pull. Skipped on a first build.
    prev=()
    prev_ref="docker://{{ image_registry }}/{{ image_name }}:latest"
    if skopeo inspect --raw "$prev_ref" >/dev/null 2>&1; then
        prev=(--previous-build "$prev_ref")
        echo "basing layer plan on ${prev_ref}"
    else
        echo "no published image yet; letting rpm-ostree choose a fresh layer plan"
    fi
    # If the ref holds an image from a different base (the older hand-built vespera was
    # layered on bazzite-nvidia-open), the first rechunk gains little. Self-corrects.

    before=$(podman inspect "$img" | jq '.[0].RootFS.Layers | length')
    # NOT mktemp's default. The intermediate oci-archive is about the size of the image
    # (~15 GB), and on Fedora Atomic /tmp is a RAM-backed tmpfs roughly half of RAM — the
    # write either hits ENOSPC or eats memory. output/ is disk-backed, gitignored, and
    # already what `just clean` removes.
    mkdir -p output
    # Absolute: podman treats a relative --volume source as a NAMED VOLUME and fails.
    out="$(mktemp -d -p "$PWD/output")"
    trap 'rm -rf "$out"' EXIT

    # rpm-ostree runs INSIDE the image, so the image's own strict signing policy applies
    # and --previous-build cannot read the published manifest, failing with
    #   "A signature was required, but no signature exists"
    # That bites on every unsigned previous image, including the first signed build (whose
    # predecessor is unsigned by definition), and the workflow's continue-on-error would
    # turn it into a silently unchunked image. Reading a layer PLAN is not a trust
    # decision: the rootfs comes from --rootfs below, nothing from the remote image is
    # unpacked or executed, and layer boundaries only affect download size. So this
    # throwaway builder container gets a permissive policy; the SHIPPED
    # /etc/containers/policy.json is untouched and stays strict.
    printf '{"default":[{"type":"insecureAcceptAnything"}]}\n' >"$out/policy.json"

    podman run --rm --privileged --pull=never \
      --mount=type=image,src="$img",target=/rpm-ostree \
      --volume "$out:/run/out:Z" \
      --volume "$out/policy.json:/etc/containers/policy.json:ro" \
      --entrypoint /usr/bin/rpm-ostree \
      "$img" \
      compose build-chunked-oci \
        --bootc \
        --format-version 2 \
        --max-layers "$max_layers" \
        "${prev[@]}" \
        "${label_args[@]}" \
        --rootfs /rpm-ostree \
        --output oci-archive:/run/out/chunked.oci

    new=$(podman pull "oci-archive:$out/chunked.oci")
    podman tag "$new" "$img"
    after=$(podman inspect "$img" | jq '.[0].RootFS.Layers | length')
    echo "rechunked: ${before} layer(s) -> ${after} layer(s)"

# Show the layer count — a single fat layer means every update re-downloads all of it
layers tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    podman inspect "localhost/{{ image_name }}:{{ tag }}" \
      | jq -r '.[0].RootFS.Layers | length as $n | "layers: \($n)"'
    echo "(run 'just rechunk' to split it)"

# Show what the build actually installed, as a sorted manifest
manifest tag=default_tag:
    podman run --rm "{{ image_name }}:{{ tag }}" \
        rpm -qa --queryformat '%{NAME}\t%{VERSION}-%{RELEASE}\t%{VENDOR}\n' | sort

# Diff the package set against the base image
diff-base tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail
    base_image=$(grep -oP '^ARG BASE_IMAGE="\K[^"]+' Containerfile)
    base_tag=$(grep -oP '^ARG BASE_TAG="\K[^"]+' Containerfile)
    q='rpm -qa --queryformat %{NAME}\n'
    diff <(podman run --rm "${base_image}:${base_tag}" $q | sort) \
         <(podman run --rm "{{ image_name }}:{{ tag }}" $q | sort) \
         || true

# Open a shell in a built image to poke at it
inspect tag=default_tag:
    podman run --rm -it "{{ image_name }}:{{ tag }}" /bin/bash

# ---------------------------------------------------------------------------
# Disk artifacts
# ---------------------------------------------------------------------------

# Build a bootable artifact from a local image: iso | qcow2 | raw
# The optional third argument overrides the bib config, for throwaway variants (a disk
# with sshd enabled for scripted smoke-testing, say) without editing the real ones.
disk target="qcow2" tag=default_tag config_override="":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ target }}" in
      iso)   type=anaconda-iso; config=disk_config/iso-kde.toml ;;
      qcow2) type=qcow2;        config=disk_config/disk.toml ;;
      raw)   type=raw;          config=disk_config/disk.toml ;;
      *) echo "target must be iso, qcow2 or raw" >&2; exit 1 ;;
    esac
    if [[ -n "{{ config_override }}" ]]; then
      config="{{ config_override }}"
      [[ -f "$config" ]] || { echo "no such config: $config" >&2; exit 1; }
      echo "using config override: $config"
    fi
    mkdir -p output

    # `just build` is ROOTLESS, so the image lands in the user graphroot. bootc-image-builder
    # runs as root and reads root's storage, so the image has to be copied across first or
    # bib fails with "image not found". ublue's image-template does this in
    # _rootful_load_image, which its _build-bib recipe depends on.
    #
    # Compare image IDs rather than mere existence: after a rebuild root still holds the
    # PREVIOUS image, and an `image exists` check would silently build a disk from it.
    img="localhost/{{ image_name }}:{{ tag }}"
    user_id="$(podman inspect "$img" | jq -r '.[0].Id')"
    root_id="$(sudo podman inspect "$img" 2>/dev/null | jq -r '.[0].Id' || true)"
    if [[ "$user_id" != "$root_id" ]]; then
      echo "copying $img into root storage (bib reads it from there)"
      # TMPDIR under output/: the intermediate is image-sized and /tmp is a RAM-backed
      # tmpfs on Atomic. ublue redirects TMPDIR to $PWD for the same reason.
      scptmp="$(mktemp -d -p output)"
      sudo TMPDIR="$scptmp" podman image scp "${UID}@localhost::$img" "root@localhost::$img"
      rm -rf "$scptmp"
    fi

    # --privileged: the builder needs loop devices and mount(2).
    # --rootfs: REQUIRED. bib infers the root filesystem from /usr/lib/bootc/install/ in
    #   the source image, and neither this image nor the ublue base ships that directory,
    #   so bib aborts with "missing required info: DefaultRootFs". btrfs matches what
    #   disk_config/disk.toml documents and what ublue's image-template passes.
    # --local is not passed: bib now defaults to local storage and warns if it is given.
    # --chown hands the output back inside this same privileged run. A trailing
    #   `sudo chown -R ... output` used to do it, but bib takes long enough that sudo's
    #   credential cache expires, so an unattended build failed on its very last line with
    #   "sudo: timed out reading password" and left a root-owned qcow2 behind.
    sudo podman run --rm -it --privileged \
      --security-opt label=type:unconfined_t \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      -v "$PWD/output:/output" \
      -v "$PWD/${config}:/config.toml:ro" \
      "{{ bib_image }}" \
      --type "${type}" --use-librepo=True --rootfs btrfs \
      --chown "$(id -u):$(id -g)" \
      "localhost/{{ image_name }}:{{ tag }}"
    ls -lh output

# Boot the qcow2 in QEMU to smoke-test it
run-vm:
    qemu-system-x86_64 \
        -enable-kvm -M q35 -cpu host -smp 4 -m 8192 \
        -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \
        -drive file=output/qcow2/disk.qcow2,if=virtio \
        -display gtk

# ---------------------------------------------------------------------------
# Signing
# ---------------------------------------------------------------------------

# Generate a cosign keypair: commit cosign.pub, put cosign.key in SIGNING_SECRET
gen-keys:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -e cosign.key ]]; then
        echo "cosign.key already exists here — refusing to overwrite" >&2
        exit 1
    fi
    # Empty password: the key lives in a GitHub secret, not behind a prompt.
    COSIGN_PASSWORD="" cosign generate-key-pair
    echo
    echo "Next:"
    echo "  gh secret set SIGNING_SECRET < cosign.key"
    echo "  git add cosign.pub && git commit -m 'chore: add signing public key'"
    echo "  shred -u cosign.key      # .gitignore already excludes it"

# Verify a published image against cosign.pub
verify tag=default_tag:
    cosign verify --key cosign.pub "{{ image_registry }}/{{ image_name }}:{{ tag }}"

# ---------------------------------------------------------------------------
# Housekeeping
# ---------------------------------------------------------------------------

# Format this justfile in place
fmt:
    just --unstable --fmt -f Justfile

# Remove local build output and dangling podman layers
clean:
    rm -rf output
    podman image prune -f
