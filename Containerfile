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

# Aurora-style /opt fix - makes /opt writable for downstream/user packages
RUN rm -rf /opt && ln -s /var/opt /opt

# Validate
RUN bootc container lint

CMD ["/sbin/init"]
