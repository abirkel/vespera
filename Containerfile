ARG BASE_IMAGE="ghcr.io/ublue-os/bazzite-nvidia:latest@sha256:06dc7a19eabdb312b6fefbee07b3a7384e3c7d02bee5f3dbf62cfa420b609972"

FROM scratch AS ctx
COPY system_files /files
COPY build_files /build_files
COPY flatpaks /flatpaks

FROM ${BASE_IMAGE}

#ARG IMAGE_NAME="${IMAGE_NAME:-vespera}"
#ARG IMAGE_VENDOR="${IMAGE_VENDOR:-abirkel}"
ARG IMAGE_NAME="bazzite-nvidia"
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
