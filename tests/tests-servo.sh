#!/usr/bin/env bash
#
# The tests.sh suite, run against the chromeless "servo" flavor instead of
# servoshell. Everything else (deps, smoke page, headless load) is identical,
# so this just points SERVO_PKGNAME at the other package and sources it
#
# SPDX-FileCopyrightText: Björn Busse <bj.rn@baerlin.eu>
# SPDX-License-Identifier: BSD-3-Clause

export SERVO_PKGNAME=servo

# shellcheck source=tests/tests.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tests.sh"
