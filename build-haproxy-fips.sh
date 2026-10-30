#!/usr/bin/env bash
set -euo pipefail

# --- configuration -----------------------------------------------------------

REPO_URL="${REPO_URL:-https://github.com/haproxy/haproxy}"
BASE_IMAGE="${BASE_IMAGE:-ghcr.io/gardenlinux/gardenlinux/fips:1877.22}"
WORKDIR="${WORKDIR:-.build/haproxy-fips-build}"
IMAGE_NAME="${IMAGE_NAME:-gl-fips-haproxy}"
ARCH="${ARCH:-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')}"
VERSION="${VERSION:-3.5-dev10}"
UPSTREAM_GIT_SHA="${UPSTREAM_GIT_SHA:-64a335366dc1bb5431e28a75e3a22e4226ac9b8f}"

# --- prerequisites -----------------------------------------------------------

check_tool() { command -v "$1" &>/dev/null || { echo "error: $1 not found" >&2; exit 1; }; }
check_tool git
check_tool docker
docker buildx version &>/dev/null || { echo "error: docker buildx not available" >&2; exit 1; }

# --- buildx driver -----------------------------------------------------------

if ! docker buildx inspect fips-builder &>/dev/null; then
    docker buildx create --name fips-builder --driver docker-container
fi
docker buildx use fips-builder

# --- prepare build directory -------------------------------------------------

mkdir -p "${WORKDIR}"

# --- generate Dockerfile.fips ------------------------------------------------

cat > "${WORKDIR}/Dockerfile.fips" <<'DOCKERFILE'
ARG BASE_IMAGE
FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS builder
ARG VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc \
        make \
        libssl-dev \
        libpcre2-dev \
        zlib1g-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .

RUN make -j$(nproc) \
        TARGET=linux-glibc \
        USE_OPENSSL=1 \
        USE_PCRE2=1 \
        USE_PCRE2_JIT=1 \
        USE_ZLIB=1 \
        USE_THREAD=1 \
        USE_GETADDRINFO=1 \
        PREFIX=/usr/local \
        DESTDIR=/install \
    && make install-bin \
        PREFIX=/usr/local \
        DESTDIR=/install

FROM ${BASE_IMAGE}
ARG UPSTREAM_GIT_SHA

LABEL org.opencontainers.image.description="A FIPS-enabled HAProxy image"
LABEL org.opencontainers.image.licenses="GPL-2.0-only"
LABEL org.opencontainers.image.revision="${UPSTREAM_GIT_SHA}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpcre2-8-0 \
        zlib1g \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -r -s /sbin/nologin -u 99 haproxy

COPY --from=builder /install/usr/local/sbin/haproxy /usr/local/sbin/haproxy

EXPOSE 8080
EXPOSE 8404

USER haproxy

ENTRYPOINT ["/usr/local/sbin/haproxy"]
CMD ["-W", "-db", "-f", "/etc/haproxy/haproxy.cfg"]
DOCKERFILE

# --- clone / checkout source -------------------------------------------------

CLONE_DIR=".build/fips-port-haproxy"

if [ ! -d "${CLONE_DIR}/.git" ]; then
    git clone "${REPO_URL}" "${CLONE_DIR}"
fi

pushd "${CLONE_DIR}" > /dev/null
git checkout "v${VERSION}"
popd > /dev/null

# --- build -------------------------------------------------------------------

docker buildx build \
    --platform "linux/${ARCH}" \
    --build-arg BASE_IMAGE="${BASE_IMAGE}" \
    --build-arg VERSION="${VERSION}" \
    --build-arg UPSTREAM_GIT_SHA="${UPSTREAM_GIT_SHA}" \
    --load \
    --tag "${IMAGE_NAME}:${VERSION}-${ARCH}" \
    --file "${WORKDIR}/Dockerfile.fips" \
    "${CLONE_DIR}"

# --- report ------------------------------------------------------------------

echo "Built: ${IMAGE_NAME}:${VERSION}-${ARCH}"
