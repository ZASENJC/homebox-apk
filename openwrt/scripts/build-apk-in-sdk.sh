#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.4}"
TARGET="${TARGET:?Set TARGET, for example x86}"
SUBTARGET="${SUBTARGET:?Set SUBTARGET, for example 64}"
SDK_HOST="${SDK_HOST:-Linux-x86_64}"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/openwrt/.work/${TARGET}-${SUBTARGET}}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/openwrt/dist/${TARGET}-${SUBTARGET}}"
SDK_CACHE_DIR="${SDK_CACHE_DIR:-${ROOT_DIR}/openwrt/.cache}"
SOURCE_VERSION="${SOURCE_VERSION:-}"
PNPM="${PNPM:-npm exec --yes pnpm@9.12.2 --}"
RUST_TOOLCHAIN="${RUST_TOOLCHAIN:-1.82.0}"
RUST_TARGET="${RUST_TARGET:-}"
INSTALL_RUSTUP="${INSTALL_RUSTUP:-1}"
SKIP_WEB_BUILD="${SKIP_WEB_BUILD:-0}"
SDK_EXTRACTED_DIR="${SDK_EXTRACTED_DIR:-}"
OPENWRT_FORCE_PREREQ="${OPENWRT_FORCE_PREREQ:-0}"

if [[ -z "${SOURCE_VERSION}" ]] && [[ -d "${ROOT_DIR}/.git" ]]; then
	SOURCE_VERSION="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
fi
openwrt_release_suffix="${SOURCE_VERSION:0:12}"
if [[ -z "${openwrt_release_suffix}" ]]; then
	openwrt_release_suffix="local"
fi
if [[ -d "${ROOT_DIR}/.git" ]]; then
	openwrt_release_number="$(git -C "${ROOT_DIR}" rev-list --count HEAD)"
else
	openwrt_release_number="1"
fi
PKG_RELEASE="${PKG_RELEASE:-${openwrt_release_number}}"
echo "Using OpenWrt package release ${PKG_RELEASE} for source ${openwrt_release_suffix}"

sdk_target="${TARGET}-${SUBTARGET}"
base_url="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET}/${SUBTARGET}"
sdk_pattern="openwrt-sdk-${OPENWRT_VERSION}-${sdk_target}_[^\"]+\.${SDK_HOST}\.tar\.(zst|xz)"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}" "${SDK_CACHE_DIR}"

SOURCE_ROOT="${WORK_DIR}/source"
source_tar_excludes=(
	--exclude .git
	--exclude openwrt/.work
	--exclude openwrt/.cache
	--exclude openwrt/dist
	--exclude server/target
	--exclude web/node_modules
)
if [[ "${SKIP_WEB_BUILD}" != "1" ]]; then
	source_tar_excludes+=(--exclude build)
fi

mkdir -p "${SOURCE_ROOT}"
tar -C "${ROOT_DIR}" "${source_tar_excludes[@]}" -cf - . | tar -C "${SOURCE_ROOT}" -xf -

echo "Resolving OpenWrt SDK from ${base_url}"
if [[ -n "${SDK_EXTRACTED_DIR}" ]]; then
	sdk_dir="${WORK_DIR}/$(basename "${SDK_EXTRACTED_DIR}")"
	mkdir -p "${sdk_dir}"
	tar -C "${SDK_EXTRACTED_DIR}" -cf - . | tar -C "${sdk_dir}" -xf -
else
	sdk_archive="$(
		curl -fsSL "${base_url}/" \
			| grep -Eo "${sdk_pattern}" \
			| sort -V \
			| tail -n 1
	)"

	if [[ -z "${sdk_archive}" ]]; then
		echo "No SDK archive matched ${sdk_pattern} at ${base_url}" >&2
		exit 1
	fi

	sdk_cache_path="${SDK_CACHE_DIR}/${sdk_archive}"
	if [[ ! -f "${sdk_cache_path}" ]]; then
		curl -fL "${base_url}/${sdk_archive}" -o "${sdk_cache_path}.tmp"
		mv "${sdk_cache_path}.tmp" "${sdk_cache_path}"
	fi
	tar -xf "${sdk_cache_path}" -C "${WORK_DIR}"

	sdk_dir="$(
		find "${WORK_DIR}" -maxdepth 1 -type d -name "openwrt-sdk-*" \
			| sort \
			| head -n 1
	)"
fi

if [[ -z "${sdk_dir}" ]]; then
	echo "Unable to find extracted OpenWrt SDK directory in ${WORK_DIR}" >&2
	exit 1
fi

rm -rf "${sdk_dir}/package/homebox"
mkdir -p "${sdk_dir}/package/homebox"
tar -C "${SOURCE_ROOT}/openwrt/homebox" -cf - . | tar -C "${sdk_dir}/package/homebox" -xf -

map_rust_target() {
	case "${TARGET}/${SUBTARGET}" in
		x86/64)
			printf '%s\n' "x86_64-unknown-linux-musl"
			;;
		armsr/armv8|mediatek/filogic|rockchip/armv8|bcm27xx/bcm2711|qualcommax/ipq807x|mvebu/cortexa53|mvebu/cortexa72)
			printf '%s\n' "aarch64-unknown-linux-musl"
			;;
		armsr/armv7|ipq40xx/generic|bcm27xx/bcm2709|bcm27xx/bcm2710|mvebu/cortexa9)
			printf '%s\n' "armv7-unknown-linux-musleabihf"
			;;
		*)
			cat >&2 <<EOF
No fast rustup musl target mapping for ${TARGET}/${SUBTARGET}.
Set RUST_TARGET explicitly if this target is supported by rustup, or use the
slower OpenWrt feeds Rust path for targets that need a custom Rust std.
EOF
			exit 1
			;;
	esac
}

if [[ -z "${RUST_TARGET}" ]]; then
	RUST_TARGET="$(map_rust_target)"
fi

toolchain_cc="$(
	find "${sdk_dir}/staging_dir" -type f -path "*/bin/*-openwrt-linux-musl*-gcc" \
		| sort \
		| head -n 1
)"

if [[ -z "${toolchain_cc}" ]]; then
	echo "Unable to find OpenWrt target gcc in ${sdk_dir}/staging_dir" >&2
	exit 1
fi

toolchain_prefix="${toolchain_cc%gcc}"
target_env_suffix="${RUST_TARGET//-/_}"
target_env_suffix_upper="$(printf '%s' "${target_env_suffix}" | tr '[:lower:]' '[:upper:]')"
linker_env_name="CARGO_TARGET_${target_env_suffix_upper}_LINKER"

read -r -a pnpm_cmd <<< "${PNPM}"

run_pnpm() {
	"${pnpm_cmd[@]}" "$@"
}

load_cargo_env() {
	if [[ -f "${HOME}/.cargo/env" ]]; then
		# shellcheck disable=SC1091
		. "${HOME}/.cargo/env"
	elif [[ -f /usr/local/cargo/env ]]; then
		# shellcheck disable=SC1091
		. /usr/local/cargo/env
	fi
}

ensure_rustup() {
	if command -v rustup >/dev/null 2>&1; then
		return
	fi

	if [[ "${INSTALL_RUSTUP}" != "1" ]]; then
		echo "rustup is required; install it or set INSTALL_RUSTUP=1" >&2
		exit 1
	fi

	curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
		| sh -s -- -y --profile minimal --default-toolchain "${RUST_TOOLCHAIN}"
	load_cargo_env
}

load_cargo_env
ensure_rustup
rustup toolchain install "${RUST_TOOLCHAIN}" --profile minimal
rustup target add --toolchain "${RUST_TOOLCHAIN}" "${RUST_TARGET}"

if [[ "${SKIP_WEB_BUILD}" == "1" ]]; then
	if [[ ! -f "${SOURCE_ROOT}/build/static/index.html" ]]; then
		echo "SKIP_WEB_BUILD=1 requires existing build/static/index.html" >&2
		exit 1
	fi
	echo "Using existing frontend build from ${SOURCE_ROOT}/build"
else
	echo "Building frontend with ${PNPM}"
	(
		cd "${SOURCE_ROOT}/web"
		CI=1 run_pnpm install --frozen-lockfile
		NODE_ENV=production run_pnpm run build
	)
fi

echo "Building Homebox for ${RUST_TARGET} with ${toolchain_cc}"
export "${linker_env_name}=${toolchain_cc}"
export "CC_${target_env_suffix}=${toolchain_cc}"
if [[ -x "${toolchain_prefix}ar" ]]; then
	export "AR_${target_env_suffix}=${toolchain_prefix}ar"
fi

(
	cd "${SOURCE_ROOT}/server"
	HOMEBOX_ENV=production cargo +"${RUST_TOOLCHAIN}" build --locked --release --target "${RUST_TARGET}"
)

prebuilt_binary="${sdk_dir}/package/homebox/prebuilt/homebox"
mkdir -p "$(dirname "${prebuilt_binary}")"
cp -f "${SOURCE_ROOT}/server/target/${RUST_TARGET}/release/homebox" "${prebuilt_binary}"
chmod 0755 "${prebuilt_binary}"

cd "${sdk_dir}"

printf '%s\n' "CONFIG_PACKAGE_homebox=m" > .config
make_args=()
if [[ "${OPENWRT_FORCE_PREREQ}" == "1" ]]; then
	make_args+=(FORCE=1)
fi

make "${make_args[@]}" defconfig

if [[ -n "${OPENWRT_BUILD_JOBS:-}" ]]; then
	jobs="${OPENWRT_BUILD_JOBS}"
else
	detected_jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
	if [[ "${detected_jobs}" =~ ^[0-9]+$ ]] && (( detected_jobs > 4 )); then
		jobs=4
	else
		jobs="${detected_jobs}"
	fi
fi

make "${make_args[@]}" package/homebox/compile "-j${jobs}" V=s \
	HOMEBOX_PREBUILT="${prebuilt_binary}" \
	PKG_RELEASE="${PKG_RELEASE}"

mapfile -t apk_files < <(find "${sdk_dir}/bin/packages" -type f -name "homebox*.apk" | sort)
if [[ "${#apk_files[@]}" -eq 0 ]]; then
	echo "No homebox .apk files were produced" >&2
	exit 1
fi

rm -f "${OUTPUT_DIR}"/homebox*.apk
cp -f "${apk_files[@]}" "${OUTPUT_DIR}/"
printf 'Wrote APK artifacts to %s\n' "${OUTPUT_DIR}"
