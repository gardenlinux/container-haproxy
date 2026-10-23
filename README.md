HAProxy FIPS Port — Build Report
==================================

## Summary

HAProxy is a high-performance, open-source TCP/HTTP load balancer and proxy server written in C.
It is compiled from source and linked against the system OpenSSL library for TLS support.

### Triage results

- Primary language:  C (Makefile-based build, no go.mod/Cargo.toml/pom.xml)
- FIPS mechanism:    c-cpp-openssl — compiled against GardenLinux FIPS-enabled OpenSSL (libssl.so.3
                     from the gardenlinux:fips base image); no env var needed at runtime
- Build pattern:     Pattern D (generate Dockerfile from scratch) — no upstream Dockerfile
- License:           GPL-2.0-only (LICENSE file at repo root)

### Application metadata

- Version:           3.4.0
- Upstream git SHA:  64a335366dc1bb5431e28a75e3a22e4226ac9b8f
- FIPS library:      GardenLinux FIPS-enabled OpenSSL 3.x (libssl.so.3 from gardenlinux/fips base)

### Docker images built

| Image              | Tag          | Size  |
|--------------------|--------------|-------|
| gl-fips-haproxy    | 3.4.0-amd64  | 46 MB |

---

## Steps taken

- Cloned https://github.com/haproxy/haproxy to .build/fips-port-haproxy and checked out v3.4.0.

- Triage: C project with Makefile build. No upstream Dockerfile. Pattern D chosen with a
  hand-written Dockerfile.fips that compiles haproxy inside the gardenlinux FIPS base image so
  it links against the FIPS-enabled libssl.so.3 provided there.

- Build flags: USE_OPENSSL=1 links against libssl-dev from the gardenlinux apt repo (which
  is the same FIPS-enabled OpenSSL as in the runtime image). USE_PCRE2=1 + USE_PCRE2_JIT=1
  for full regex support. USE_ZLIB=1 for HTTP compression. USE_THREAD=1 for multi-threading.
  TARGET=linux-glibc for glibc-based Linux. All build dependencies installed via apt-get in
  the builder stage; only the runtime libs (libpcre2-8-0, zlib1g) are installed in the final image.

- Runtime user: UID 99 (haproxy) created with useradd -r. This matches the conventional UID
  used for haproxy in many distributions.

- Port exposure: 8080 (frontend default) and 8404 (stats endpoint convention).

- Fix applied (arch suffix): initial script tagged image as ${VERSION} without -${ARCH} suffix;
  corrected to ${VERSION}-${ARCH}.

- Fix applied (UPSTREAM_GIT_SHA label): the initial script had the SHA hardcoded as a string
  literal in the LABEL line inside the heredoc. Fixed by adding ARG UPSTREAM_GIT_SHA to the
  final stage and passing it via --build-arg so the label value is dynamic.

- Fix applied (ARCH make variable): the initial script passed ARCH=${TARGETARCH} to make, which
  in HAProxy 3.x emits a deprecation warning ("ARCH variable was forced but is no longer used").
  Removed ARCH= from the make invocation and dropped the now-unused ARG TARGETARCH from the
  Dockerfile.

---

## Test script output (final run)

  - Based on Garden Linux (NAME="Garden Linux" in /etc/os-release)              PASS
  - FIPS-enabled gardenlinux variant (VARIANT_ID=container-sslfips-amd64)       PASS
  - Runs as non-root user (whoami → haproxy / UID 99)                           PASS
  - Linked with libssl.so.3                                                      PASS
  - libssl.so.3 contains FIPS string                                             PASS
  - libssl.so.3 is OpenSSL (not aws-lc, not BoringSSL)                          PASS
  - haproxy uses same libssl.so.3 as gardenlinux openssl binary                 PASS
  - org.opencontainers.image.description label present                           PASS
  - org.opencontainers.image.licenses=GPL-2.0-only label present                PASS
  - org.opencontainers.image.revision=64a335366... label present                 PASS

---

## Kubernetes (k3d) test results

Cluster: fips-test (k3d, single-server)
Import method: manual `ctr -n k8s.io images import` (k3d's built-in import tool silently failed
to register the image in the k8s.io containerd namespace for this image; direct import worked).

| Image                        | Pod status  | Notes                              | Result |
|------------------------------|-------------|------------------------------------|--------|
| gl-fips-haproxy:3.4.0-amd64  | Completed   | `haproxy -v` printed version + exit 0 | PASS |

Pod logs:
  HAProxy version 3.4.0 2026/06/03 - https://haproxy.org/
  Status: long-term supported branch - will stop receiving fixes around Q2 2031.
  Known bugs: http://www.haproxy.org/bugs/bugs-3.4.0.html
  Running on: Linux 7.0.0-34-generic #34-Ubuntu SMP PREEMPT_DYNAMIC ... x86_64
