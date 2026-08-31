#!/usr/bin/env bash
#
# bash_unit tests: install the released servo apk into moonshine-sway and
# load a URL with it.
#
# moonshine-sway is musl + brush with no wget/curl, so the apk is fetched on
# the host and copied in. build-apk.yml builds with !tracedeps, so the apk
# declares no shared-library dependencies and they are listed here by hand.
#
# SPDX-FileCopyrightText: Björn Busse <bj.rn@baerlin.eu>
# SPDX-License-Identifier: BSD-3-Clause

ENGINE="${ENGINE:-podman}"
BASE_IMAGE="${BASE_IMAGE:-ghcr.io/bbusse/moonshine-sway-web:latest}"

# Which flavor to exercise: servoshell (upstream) or servo (chromeless). It is
# the pkgname, the release asset name and the installed binary. tests-servo.sh
# is a thin wrapper that sets this to servo
SERVO_PKGNAME="${SERVO_PKGNAME:-servoshell}"
TEST_IMAGE="${TEST_IMAGE:-moonshine-sway-${SERVO_PKGNAME}:test}"

SERVO_VERSION="${SERVO_VERSION:-0.5.0}"
SERVO_PKGREL="${SERVO_PKGREL:-0}"
RELEASE_URL="${RELEASE_URL:-https://github.com/bbusse/alpine-servo-build/releases/download}"

SERVO_RUNTIME_DEPS="dbus-libs eudev-libs fontconfig freetype harfbuzz \
libstdc++ libunwind libxkbcommon wayland-libs-client wayland-libs-egl"

setup_suite() {
    local root tmp arch asset
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    tmp="$(mktemp -d)"
    SUITE_TMP="$tmp"

    case "$(uname -m)" in
    x86_64)          arch=x86_64 ;;
    aarch64|arm64)   arch=aarch64 ;;
    *) echo "unsupported host arch: $(uname -m)" >&2; return 1 ;;
    esac

    asset="${arch}-${SERVO_PKGNAME}-${SERVO_VERSION}-r${SERVO_PKGREL}.${arch}.apk"
    if ! curl -fsSL -o "$tmp/servo.apk" \
            "${RELEASE_URL}/v${SERVO_VERSION}/${asset}"; then
        echo "could not fetch ${asset} from ${RELEASE_URL}/v${SERVO_VERSION}" >&2
        echo "a servo release must exist before this suite can run" >&2
        return 1
    fi

    cp "$root/keys/apk-releases.rsa.pub" "$tmp/"

    cat > "$tmp/index.html" <<'HTML'
<!doctype html>
<title>servo smoke</title>
<h1>servo smoke test</h1>
HTML

    cat > "$tmp/Containerfile" <<CONTAINERFILE
FROM ${BASE_IMAGE}
COPY apk-releases.rsa.pub /etc/apk/keys/apk-releases.rsa.pub
COPY servo.apk /tmp/servo.apk
COPY index.html /srv/index.html
RUN apk add --no-cache ${SERVO_RUNTIME_DEPS} /tmp/servo.apk && rm /tmp/servo.apk
CONTAINERFILE

    "$ENGINE" build -t "$TEST_IMAGE" "$tmp"
}

teardown_suite() {
    [ -n "${SUITE_TMP:-}" ] && rm -rf "$SUITE_TMP"
    "$ENGINE" rmi -f "$TEST_IMAGE" >/dev/null 2>&1 || true
}

in_image() {
    "$ENGINE" run --rm --entrypoint /bin/sh "$TEST_IMAGE" -c "$1"
}

in_image_within() {
    timeout "$1" "$ENGINE" run --rm --entrypoint /bin/sh "$TEST_IMAGE" -c "$2"
}

test_apk_is_installed() {
    assert_matches "$SERVO_PKGNAME" "$(in_image "apk info -e $SERVO_PKGNAME")"
}

test_binary_present() {
    assert_status_code 0 "in_image '[ -x /usr/bin/$SERVO_PKGNAME ]'"
}

test_base_image_still_has_brush_as_sh() {
    assert_matches "brush" "$(in_image '/bin/sh --version')"
}

test_reports_version() {
    assert_matches "[Ss]ervo" "$(in_image "/usr/bin/$SERVO_PKGNAME --version")"
}

# -z/--headless renders without a compositor, -x/--exit quits once the page
# has loaded and the output image is stable, so a hang fails rather than
# blocking the suite.
test_loads_a_url_headless() {
    assert_status_code 0 \
        "in_image_within 120 '/usr/bin/$SERVO_PKGNAME --headless --exit file:///srv/index.html'"
}
