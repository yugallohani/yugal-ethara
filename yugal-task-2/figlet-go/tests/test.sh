#!/bin/bash
# Verifier entry point. Harbor copies tests/ to /tests and runs this script
# after the agent has finished. The grader is Go (the room has no Python).
set -u

mkdir -p /logs/verifier
rm -f /logs/verifier/reward.json

# Ignore any Go settings the agent may have left behind (go env -w, caches).
export GOENV=off
export GOFLAGS=
export GOPROXY=off
export GOTOOLCHAIN=local
export CGO_ENABLED=0
GOCACHE="$(mktemp -d /tmp/grade-gocache.XXXXXX)"
export GOCACHE

cd /tests && go run grade.go
status=$?

# If the grader itself could not run, still leave a valid reward file.
if [ ! -s /logs/verifier/reward.json ]; then
  echo "grader exited with status $status before writing a reward"
  echo '{"reward": 0, "build": 0, "no_python": 0, "behaviour": 0}' > /logs/verifier/reward.json
fi
exit 0
