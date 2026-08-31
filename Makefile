# SPDX-FileCopyrightText: Björn Busse <bj.rn@baerlin.eu>
# SPDX-License-Identifier: BSD-3-Clause

REMOTE ?= gh
RELEASE_BRANCH ?= ci

ENGINE ?= podman
ALPINE_VERSION ?= edge

# Which servo package/image flavor to build: servoshell (upstream, with the
# minibrowser toolbar) or servo (chromeless, toolbar patched out). It selects
# the release asset the Containerfile pulls and the image tag: servoshell
# gives :latest and servo gives :servo
FLAVOR ?= servoshell
IMAGE  ?= alpine-servo-musl:$(if $(filter servo,$(FLAVOR)),servo,latest)

# Bare version, as in alpine-brush-build: the v lives in the tag only.
# build-apk.yml normalises v$(SERVO_VERSION) into pkgver $(SERVO_VERSION).
SERVO_VERSION ?= 0.5.0
SERVO_PKGREL  ?= 0
RC            ?= 0

.PHONY: container container-servo run release release-candidate rc test help \
        _check-remote _check-branch _check-up-to-date

container: ## build the Alpine image around the released servo apk (FLAVOR=servoshell|servo)
	$(ENGINE) build \
	  --build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
	  --build-arg SERVO_VERSION=$(SERVO_VERSION) \
	  --build-arg SERVO_PKGREL=$(SERVO_PKGREL) \
	  --build-arg SERVO_PKGNAME=$(FLAVOR) \
	  -f Containerfile -t $(IMAGE) .

container-servo: ## build the chromeless "servo" image (no minibrowser toolbar)
	$(MAKE) container FLAVOR=servo

run: container ## print the engine's version from the built image
	$(ENGINE) run --rm --entrypoint $(FLAVOR) $(IMAGE) --version

_check-remote:
	@git remote get-url $(REMOTE) > /dev/null 2>&1 || \
	    { echo "Error: no remote '$(REMOTE)' — add one with: git remote add $(REMOTE) <url>"; exit 1; }

_check-branch:
	@current="$$(git rev-parse --abbrev-ref HEAD)"; \
	if [ "$$current" != "$(RELEASE_BRANCH)" ]; then \
	    echo "Error: on branch '$$current' — releases must be tagged from '$(RELEASE_BRANCH)'. Checkout $(RELEASE_BRANCH) first."; \
	    exit 1; \
	fi

_check-up-to-date: _check-remote _check-branch
	@git fetch $(REMOTE) $(RELEASE_BRANCH) > /dev/null 2>&1
	@git merge-base --is-ancestor $(REMOTE)/$(RELEASE_BRANCH) HEAD || \
	    { echo "Error: $(RELEASE_BRANCH) has commits you don't have — pull/rebase before tagging a release."; exit 1; }

# Version-based tags, not moonshine's rc-<hash>: release.yml matches
# tags: ['v*.*.*'] and reads the pkgver out of the tag name, so the tag has
# to carry the version. _rc$(RC) rather than -rc$(RC) because apk reads a
# dash as the pkgrel separator.
release: TAG := v$(SERVO_VERSION)
release: KIND := release
release-candidate rc: TAG := v$(SERVO_VERSION)_rc$(RC)
release-candidate rc: KIND := release candidate

release release-candidate rc: _check-up-to-date ## tag v<version> (rc: v<version>_rc<n>) and push
	git tag -f $(TAG)
	@printf 'Tagged %s as %s\n' "$$(git rev-parse --short HEAD)" "$(TAG)"
	@printf 'Push tag to trigger a %s? [y/N] ' "$(KIND)" && read ans && \
	    case "$$ans" in [yY]) git push $(REMOTE) $(TAG) ;; \
	    *) git tag -d $(TAG); echo 'Aborted — tag removed.' ;; esac

help: ## list targets
	@grep -hE '^[a-z][a-z0-9 -]*:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/' | expand -t20
