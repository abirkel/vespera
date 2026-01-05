ARG BASE_IMAGE="ghcr.io/ublue-os/bazzite-nvidia:latest@sha256:e616eed133df8f26ef345dfc361eb00e125926998e4dd37ecbc057bee1a8907e"

FROM scratch AS ctx
COPY system_files /files
COPY build_files /build_files
COPY flatpaks /flatpaks

FROM ${BASE_IMAGE}

ARG IMAGE_NAME="${IMAGE_NAME:-vespera}"
ARG IMAGE_VENDOR="${IMAGE_VENDOR:-abirkel}"

# Copy system files first
COPY --from=ctx /files /

# Run build scripts
RUN --mount=type=tmpfs,dst=/tmp \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    mkdir -p /var/roothome && \
    /ctx/build_files/build.sh

# Disable terra-mesa repo to fix bootc-image-builder ISO build failures
# Issue: The terra-release-mesa package (from Bazzite base) creates a repo config
# that references a GPG key at /etc/pki/rpm-gpg/RPM-GPG-KEY-terra43-mesa, but this
# file doesn't exist in the container. During container builds this is fine because
# packages are already installed, but bootc-image-builder's dependency resolution
# tries to verify all enabled repos and fails when it can't find the GPG key.
# Since Mesa is already installed in the base image and users won't need to layer
# Mesa packages, disabling this repo is safe and prevents ISO build failures.
# See: https://discussion.fedoraproject.org/t/howto-install-fyra-labs-terra-repository-on-traditional-and-atomic-fedora/124522
# Terra repos are noted as "in early development" and have known GPG key issues.
RUN if [ -f /etc/yum.repos.d/terra-mesa.repo ]; then \
        sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/terra-mesa.repo; \
        echo "Disabled terra-mesa repo due to missing GPG key"; \
    fi

# Aurora-style /opt fix - makes /opt writable for downstream/user packages
RUN rm -rf /opt && ln -s /var/opt /opt

# Validate
RUN bootc container lint

CMD ["/sbin/init"]
