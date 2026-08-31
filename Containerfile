ARG ALPINE_VERSION=edge
FROM alpine:${ALPINE_VERSION}
LABEL maintainer="Björn Busse <bj.rn@baerlin.eu>"
LABEL org.opencontainers.image.source=https://github.com/bbusse/alpine-servo-build
LABEL org.opencontainers.image.description="Alpine Linux with Servo, a web browser engine, built natively for musl"

# Must match a tag published by release.yml (git tag <version>) and the
# pkgrel abuild built it with (see build-apk.yml, default pkgrel: 0).
# The tag may carry a packaging suffix, so this is the full version
ARG SERVO_VERSION=0.5.0
ARG SERVO_PKGREL=0

# Which flavor's package to install: "servoshell" (default, minibrowser
# toolbar and all) or "servo" (the chromeless build). It is the apk pkgname,
# the release asset name, and the installed binary at /usr/bin/${SERVO_PKGNAME}
ARG SERVO_PKGNAME=servoshell

COPY keys/apk-releases.rsa.pub /etc/apk/keys/apk-releases.rsa.pub

ARG TARGETARCH
RUN case "${TARGETARCH}" in \
      amd64) APK_ARCH=x86_64 ;; \
      arm64) APK_ARCH=aarch64 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && wget -qO /tmp/servo.apk \
         "https://github.com/bbusse/alpine-servo-build/releases/download/v${SERVO_VERSION}/${APK_ARCH}-${SERVO_PKGNAME}-${SERVO_VERSION}-r${SERVO_PKGREL}.${APK_ARCH}.apk" \
    # The packaged apk only ships the servoshell binary itself (see
    # build-apk.yml's generic APKBUILD, which disables dependency tracing),
    # so pull its shared-library dependencies in from Alpine's own repos
    # alongside it. This list is a first-pass best effort - our build
    # deliberately drops the media-gstreamer/webgpu/webxr/gamepad features
    # (see release.yml), so it excludes the GStreamer/GLib stack the
    # upstream glibc release links; refine once we've inspected the actual
    # ELF NEEDED entries of our own build.
    && apk add --no-cache \
         dbus-libs \
         eudev-libs \
         fontconfig \
         harfbuzz \
         libstdc++ \
         libunwind \
         libx11 \
         libxcb \
         libxkbcommon \
         mesa-gl \
         vulkan-loader \
         wayland-libs-client \
         /tmp/servo.apk \
    && rm /tmp/servo.apk

# ARG is gone at run time; carry the binary name in as an ENV so the exec form
# entrypoint can still forward `docker run <image> ...` args to it unchanged
ENV SERVO_PKGNAME=${SERVO_PKGNAME}
ENTRYPOINT ["/bin/sh", "-c", "exec \"$SERVO_PKGNAME\" \"$@\"", "sh"]
