#!/bin/bash
# Build .deb, .rpm, and .archlinux packages for anteater.
set -euo pipefail

VERSION="${ANTEATER_VERSION:-1.0.0}"
GOOS="${GOOS:-linux}"
GOARCH="${GOARCH:-amd64}"

case "$GOARCH" in
    amd64) ARCH="amd64" ;;
    arm64) ARCH="arm64" ;;
    *)
        echo "Unsupported GOARCH: $GOARCH" >&2
        exit 1
        ;;
esac

# Build aa-analyze for target arch
BINARY="dist/aa-analyze-${GOOS}-${GOARCH}"
if [[ ! -f "$BINARY" ]]; then
    echo "Building aa-analyze for ${GOOS}/${GOARCH}..."
    GOOS="$GOOS" GOARCH="$GOARCH" CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$BINARY" ./cmd/aa-analyze
fi

mkdir -p dist/packages

NFPM="$(command -v nfpm || echo /home/clxud/go/bin/nfpm)"

echo "Building packages for ${GOOS}/${GOARCH} (arch: ${ARCH})"
export NFPM_ARCH="$ARCH" GOOS GOARCH VERSION

for FORMAT in deb rpm archlinux; do
    echo "  → ${FORMAT}..."
    "$NFPM" package \
        --config packaging/nfpm.yaml \
        --packager "$FORMAT" \
        --target dist/packages/
done

echo "Done:"
ls -lh dist/packages/
