ARG BASE_IMAGE="ghcr.io/ublue-os/bazzite-nvidia-open:latest@sha256:9d1c1ababec12feb8421984ee54e83ad8a9a0a6878a89ceaf6ffddabf745415a"

FROM scratch AS ctx
COPY system_files /files
COPY build_files /build_files
COPY flatpaks /flatpaks

FROM ${BASE_IMAGE}

#ARG IMAGE_NAME="${IMAGE_NAME:-vespera}"
#ARG IMAGE_VENDOR="${IMAGE_VENDOR:-abirkel}"
ARG IMAGE_NAME="bazzite-nvidia-open"
ARG IMAGE_VENDOR="ublue-os"

# Copy cosign public key for image signature verification
COPY cosign.pub /etc/pki/containers/vespera.pub

# Copy system files first
COPY --from=ctx /files /

# Run build scripts
RUN --mount=type=tmpfs,dst=/tmp \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    mkdir -p /var/roothome && \
    /ctx/build_files/build.sh

# Aurora-style /opt fix - makes /opt writable for downstream/user packages
RUN rm -rf /opt && ln -s /var/opt /opt

# Fix for bootc-image-builder vendor detection with new Fedora EFI paths
# See: https://github.com/osbuild/bootc-image-builder/issues/1171
RUN mkdir -p /usr/lib/bootupd/updates && cp -r /usr/lib/efi/*/*/* /usr/lib/bootupd/updates

# Validate
RUN bootc container lint

CMD ["/sbin/init"]
