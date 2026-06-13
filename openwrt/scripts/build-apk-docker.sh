#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${OPENWRT_BUILDER_IMAGE:-node:22-bookworm-slim}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.4}"
TARGET="${TARGET:?Set TARGET, for example x86}"
SUBTARGET="${SUBTARGET:?Set SUBTARGET, for example 64}"
SOURCE_VERSION="${SOURCE_VERSION:-$(git -C "${ROOT_DIR}" rev-parse HEAD 2>/dev/null || true)}"
PNPM="${PNPM:-npm exec --yes pnpm@9.12.2 --}"
OPENWRT_BUILD_JOBS="${OPENWRT_BUILD_JOBS:-}"
RUST_TOOLCHAIN="${RUST_TOOLCHAIN:-1.82.0}"
RUST_TARGET="${RUST_TARGET:-}"
SKIP_WEB_BUILD="${SKIP_WEB_BUILD:-0}"
SDK_EXTRACTED_DIR="${SDK_EXTRACTED_DIR:-}"
INSTALL_BUILD_DEPS="${INSTALL_BUILD_DEPS:-1}"
OPENWRT_FORCE_PREREQ="${OPENWRT_FORCE_PREREQ:-0}"

docker run --rm \
	--platform "${DOCKER_PLATFORM}" \
	-v "${ROOT_DIR}:/work" \
	-w /work \
	-e OPENWRT_VERSION="${OPENWRT_VERSION}" \
	-e TARGET="${TARGET}" \
	-e SUBTARGET="${SUBTARGET}" \
	-e SOURCE_VERSION="${SOURCE_VERSION}" \
	-e WORK_DIR=/tmp/homebox-openwrt-"${TARGET}"-"${SUBTARGET}" \
	-e OUTPUT_DIR=/work/openwrt/dist/"${TARGET}"-"${SUBTARGET}" \
	-e SDK_CACHE_DIR=/work/openwrt/.cache \
	-e PNPM="${PNPM}" \
	-e OPENWRT_BUILD_JOBS="${OPENWRT_BUILD_JOBS}" \
	-e RUST_TOOLCHAIN="${RUST_TOOLCHAIN}" \
	-e RUST_TARGET="${RUST_TARGET}" \
	-e SKIP_WEB_BUILD="${SKIP_WEB_BUILD}" \
	-e SDK_EXTRACTED_DIR="${SDK_EXTRACTED_DIR}" \
	-e INSTALL_BUILD_DEPS="${INSTALL_BUILD_DEPS}" \
	-e OPENWRT_FORCE_PREREQ="${OPENWRT_FORCE_PREREQ}" \
	"${IMAGE}" \
	bash -lc '
		set -euo pipefail
		if [[ "${INSTALL_BUILD_DEPS}" = "1" ]]; then
			apt-get -o Acquire::Retries=5 update
			DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
				build-essential \
				ca-certificates \
				curl \
				file \
				gawk \
				gettext \
				git \
				libncurses-dev \
				libssl-dev \
				python3 \
				python3-setuptools \
				rsync \
				unzip \
				wget \
				xz-utils \
				zstd
		else
			command -v gawk >/dev/null 2>&1 || { echo "INSTALL_BUILD_DEPS=0 requires GNU awk (gawk)" >&2; exit 1; }
			command -v rsync >/dev/null 2>&1 || { echo "INSTALL_BUILD_DEPS=0 requires rsync" >&2; exit 1; }
		fi
		openwrt/scripts/build-apk-in-sdk.sh
	'
