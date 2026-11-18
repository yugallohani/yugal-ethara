# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1 ("source"): fetch pyfiglet at a pinned commit and finish its setup.
# git and the rest of this image never reach the final room.
# ---------------------------------------------------------------------------
FROM alpine/git:v2.47.2@sha256:062a01ad7a0eb17cff382bc5e26086b4d710e56dfdfdf001109a49b6d9bd378c AS source

ARG PYFIGLET_REPO=https://github.com/pwaller/pyfiglet
ARG PYFIGLET_SHA=255827efbc09d662875dad50fa0edc1e1263bf45

RUN git clone "$PYFIGLET_REPO" /src \
 && cd /src \
 && git checkout --quiet "$PYFIGLET_SHA" \
 && test "$(git rev-parse HEAD)" = "$PYFIGLET_SHA" \
 && rm -rf .git pyfiglet/fonts-contrib test-fonts \
 # Font setup from the Makefile ("clean" + "minimal"): the code loads fonts
 # from pyfiglet/fonts/, but the repository ships them in fonts-standard/.
 && rm -rf pyfiglet/fonts \
 && mkdir pyfiglet/fonts \
 && cp pyfiglet/fonts-standard/* pyfiglet/fonts/

# ---------------------------------------------------------------------------
# Stage 2: the agent's room. Go on Alpine (no Python), bash for Harbor,
# and a normal user "player" who owns the repository.
# ---------------------------------------------------------------------------
FROM golang:1.23-alpine@sha256:383395b794dffa5b53012a212365d40c8e37109a626ca30d6151c8348d380b5f

RUN apk add --no-cache bash \
 && adduser -D -u 1000 -s /bin/bash player \
 && mkdir -p /workspace

COPY --from=source --chown=player:player /src /workspace/repo

ENV CGO_ENABLED=0 \
    GOTOOLCHAIN=local

USER player
WORKDIR /workspace/repo
