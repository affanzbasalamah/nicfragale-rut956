#!/bin/bash
# build_rut956.bash — ziti-edge-tunnel cross-compiler for Teltonika RUT956
# Based on NicFragale/NetFoundry OpenZITI-OWRT OWRT_Builder.bash
# Adaptations: mipsel_24kc arch, Teltonika GPL SDK toolchain, OpenSSL no-asm overlay
MY_NAME="RUT956_Builder"
MY_VERSION="20260509"

# ── Parameters ────────────────────────────────────────────────────────────────
ZT_TUNVER="${1:-latest}"
ZT_TUNBRANCH="${2}"
ZT_TUNVER="${ZT_TUNVER#v}"   # strip leading 'v' if provided

# ── RUT956 Fixed Config ───────────────────────────────────────────────────────
GPL_SDK="/home/affan/teltonika/RUT9M_R_GPL_00.07.22.1"
TOOLCHAIN_DIR="${GPL_SDK}/staging_dir/toolchain-mipsel_24kc_gcc-8.4.0_musl"
export STAGING_DIR="${GPL_SDK}/staging_dir"

ZT_ARCH="mipsel"
CROSS_PREFIX="mipsel-openwrt-linux-musl"

# ── Build Infrastructure ──────────────────────────────────────────────────────
ZT_TUNURL="https://github.com/openziti/ziti-tunnel-sdk-c"
VCPKG_URL="https://github.com/microsoft/vcpkg"
ZT_CMAKEMINVER=("3" "24" "0")
ZT_WORKDIR="/home/affan/teltonika/rut956-builds"

# ── Helpers ───────────────────────────────────────────────────────────────────
ZT_STEP=0
function GTE()  { printf '\e[1;31mERROR: Early exit at Step %s\e[0m\n' "${1}"; exit "${1}"; }
function STEP() { printf '\n\e[1;33mStep %d: %s\e[0m\n' "$((++ZT_STEP))" "${1}"; }
function INFO() { printf '\e[0;34m  >> %s\e[0m\n' "${1}"; }

function resolve_latest_version() {
    wget -qO- "${ZT_TUNURL}/tags" 2>/dev/null \
        | awk 'match($0,/v[0-9]+\.[0-9]+\.[0-9]+/) {
            v=substr($0,RSTART+1,RLENGTH-1)
            if (!seen[v]++) print v
          }' \
        | sort -t'.' -k1,1rn -k2,2rn -k3,3rn \
        | head -1
}

function check_cmake_version() {
    local ver maj min patch
    ver=$(cmake --version 2>/dev/null | awk '/^cmake version/ {print $3}')
    IFS='.' read -r maj min patch <<< "${ver:-0.0.0}"
    maj="${maj:-0}"; min="${min:-0}"; patch="${patch:-0}"
    if [[ "${maj}" -gt "${ZT_CMAKEMINVER[0]}" ]] \
    || [[ "${maj}" -eq "${ZT_CMAKEMINVER[0]}" && "${min}" -gt "${ZT_CMAKEMINVER[1]}" ]] \
    || [[ "${maj}" -eq "${ZT_CMAKEMINVER[0]}" && "${min}" -eq "${ZT_CMAKEMINVER[1]}" \
          && "${patch}" -ge "${ZT_CMAKEMINVER[2]}" ]]; then
        INFO "CMake ${ver} — OK"
        return 0
    fi
    INFO "CMake ${ver:-not found} < 3.24.0 — upgrading via Kitware PPA"
    apt-get remove -y --purge --auto-remove cmake 2>/dev/null
    wget -O- https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null \
        | gpg --dearmor - | tee /etc/apt/trusted.gpg.d/kitware.gpg >/dev/null
    apt-add-repository -y "deb https://apt.kitware.com/ubuntu/ $(lsb_release -cs)"
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 6AF7F09730B3F0A4
    apt-get update && apt-get install -y cmake || return 1
}

# ── Banner ────────────────────────────────────────────────────────────────────
printf '\e[1;46m %s v%s — RUT956 (mipsel_24kc musl) ziti-edge-tunnel builder \e[0m\n' \
    "${MY_NAME}" "${MY_VERSION}"

# ── Step 1: Version resolution + validation ───────────────────────────────────
STEP "Input Validation"
if [[ "${ZT_TUNVER}" == "latest" ]]; then
    INFO "Resolving latest ziti-tunnel-sdk-c version..."
    ZT_TUNVER="$(resolve_latest_version)"
    [[ -z "${ZT_TUNVER}" ]] && { INFO "ERROR: Could not resolve latest version"; GTE ${ZT_STEP}; }
fi
ZT_ROOT="${ZT_WORKDIR}/RUT956-ZT-${ZT_TUNVER}"
VCPKG_ROOT="${ZT_ROOT}/vcpkg"
VCPKG_INSTALL_ROOT="${ZT_ROOT}/vcpkg_installed"
VCPKG_OVERLAYS="${ZT_ROOT}/vcpkg-overlays"
ZT_SDKDIR="${ZT_ROOT}/ziti-tunnel-sdk-c-${ZT_TUNVER}"
TOOLCHAIN_CMAKE="${ZT_SDKDIR}/toolchains/mipsel-openwrt.cmake"

INFO "Tunnel version : ${ZT_TUNVER}"
INFO "Build root     : ${ZT_ROOT}"
INFO "Toolchain      : ${TOOLCHAIN_DIR}"
[[ -d "${TOOLCHAIN_DIR}" ]] \
    || { INFO "ERROR: Teltonika GPL SDK toolchain not found at ${TOOLCHAIN_DIR}"; GTE ${ZT_STEP}; }
[[ -x "${TOOLCHAIN_DIR}/bin/${CROSS_PREFIX}-gcc" ]] \
    || { INFO "ERROR: ${CROSS_PREFIX}-gcc not executable"; GTE ${ZT_STEP}; }
INFO "Cross-compiler : $("${TOOLCHAIN_DIR}/bin/${CROSS_PREFIX}-gcc" --version | head -1)"

# ── Step 2: Staging area ──────────────────────────────────────────────────────
STEP "Create Staging Area: ${ZT_ROOT}"
if [[ -d "${ZT_ROOT}" ]]; then
    INFO "WARNING: Staging area exists — removing in 5s (Ctrl+C to abort)"
    sleep 5
    chmod -R u+w "${ZT_ROOT}" 2>/dev/null || true
    rm -rf "${ZT_ROOT}" || GTE ${ZT_STEP}
fi
git config --global advice.detachedHead false
mkdir -vp "${ZT_ROOT}" || GTE ${ZT_STEP}
cd "${ZT_ROOT}" || GTE ${ZT_STEP}

# ── Step 3: Build dependencies ────────────────────────────────────────────────
STEP "Install Build Dependencies"
ZT_ADDLPKG=(
    autoconf automake autopoint build-essential jq
    curl doxygen expect flex cppcheck gcovr gpg
    graphviz libcap-dev libssl-dev libprotobuf-c-dev
    libsystemd-dev libtool ninja-build lsb-release
    pkg-config python3 python3-pip software-properties-common
    tar unzip wget zip zlib1g-dev gawk sed cmake
)
check_cmake_version
MISSING_PKGS=()
for pkg in "${ZT_ADDLPKG[@]}"; do
    dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "^install ok installed" || MISSING_PKGS+=("${pkg}")
done
if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    INFO "Missing packages: ${MISSING_PKGS[*]}"
    apt-get update \
        && apt-get --yes --quiet --no-install-recommends install "${MISSING_PKGS[@]}" \
        && apt-get --yes autoremove \
        && apt-get --yes autoclean \
        || GTE ${ZT_STEP}
else
    INFO "All packages already installed — skipping apt-get."
fi

# ── Step 4: Clone ziti-tunnel-sdk-c ──────────────────────────────────────────
STEP "Clone ziti-tunnel-sdk-c v${ZT_TUNVER}"
git clone --branch "${ZT_TUNBRANCH:-v${ZT_TUNVER}}" "${ZT_TUNURL}" "${ZT_SDKDIR}" \
    || GTE ${ZT_STEP}
mkdir -vp "${ZT_SDKDIR}/build" "${ZT_SDKDIR}/toolchains" || GTE ${ZT_STEP}

# ── Step 5: Bootstrap VCPKG (at the baseline commit from vcpkg.json) ─────────
VCPKG_BASELINE="$(jq -r '."builtin-baseline" // empty' "${ZT_SDKDIR}/vcpkg.json" 2>/dev/null)"
[[ -n "${VCPKG_BASELINE}" ]] \
    || { INFO "ERROR: could not read builtin-baseline from vcpkg.json"; GTE ${ZT_STEP}; }
STEP "Bootstrap VCPKG @ ${VCPKG_BASELINE}"
git clone "${VCPKG_URL}" "${VCPKG_ROOT}" || GTE ${ZT_STEP}
git -C "${VCPKG_ROOT}" checkout "${VCPKG_BASELINE}" || GTE ${ZT_STEP}
export VCPKG_FORCE_SYSTEM_BINARIES="yes"
"${VCPKG_ROOT}/bootstrap-vcpkg.sh" -disableMetrics || GTE ${ZT_STEP}
"${VCPKG_ROOT}/vcpkg" version || GTE ${ZT_STEP}
mkdir -vp "${VCPKG_ROOT}/custom-triplets"

# ── Step 6: Toolchain + VCPKG triplet files ───────────────────────────────────
STEP "Generate Toolchain Files"

cat > "${TOOLCHAIN_CMAKE}" << CMEOF
set(triple "${CROSS_PREFIX}")
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR "${ZT_ARCH}")
set(CMAKE_SYSROOT "${TOOLCHAIN_DIR}")
set(CMAKE_C_COMPILER "${TOOLCHAIN_DIR}/bin/${CROSS_PREFIX}-gcc")
set(CMAKE_CXX_COMPILER "${TOOLCHAIN_DIR}/bin/${CROSS_PREFIX}-g++")
# Include VCPKG install root so find_library/find_path resolve VCPKG packages
set(CMAKE_FIND_ROOT_PATH "${VCPKG_INSTALL_ROOT}/mipsel-linux" "${TOOLCHAIN_DIR}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
CMEOF

# Meson cross-compilation file for mipsel (used by stc and other Meson-based ports)
MESON_CROSS="${ZT_ROOT}/meson-cross-mipsel.ini"
cat > "${MESON_CROSS}" << MESONEOF
[binaries]
c = '${TOOLCHAIN_DIR}/bin/${CROSS_PREFIX}-gcc'
cpp = '${TOOLCHAIN_DIR}/bin/${CROSS_PREFIX}-g++'
ar = '${TOOLCHAIN_DIR}/bin/${CROSS_PREFIX}-ar'
strip = '${TOOLCHAIN_DIR}/bin/${CROSS_PREFIX}-strip'
pkgconfig = 'pkg-config'

[properties]
sys_root = '${TOOLCHAIN_DIR}'
c_args = ['-mips32r2', '-mtune=24kc', '-msoft-float']
cpp_args = ['-mips32r2', '-mtune=24kc', '-msoft-float']
c_link_args = ['-latomic']
cpp_link_args = ['-latomic']

[host_machine]
system = 'linux'
cpu_family = 'mips'
cpu = 'mips32'
endian = 'little'
MESONEOF

cat > "${VCPKG_ROOT}/custom-triplets/mipsel-linux.cmake" << VCEOF
set(VCPKG_TARGET_ARCHITECTURE "mipsel")
set(VCPKG_CRT_LINKAGE "dynamic")
set(VCPKG_LIBRARY_LINKAGE "static")
set(VCPKG_CMAKE_SYSTEM_NAME "Linux")
set(VCPKG_BUILD_TYPE "release")
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${TOOLCHAIN_CMAKE}")
# 32-bit MIPS lacks native 64-bit atomic instructions; provide software fallback
set(VCPKG_LINKER_FLAGS "-latomic")
# Meson cross-compilation file (required for mipsel which VCPKG Meson doesn't know)
set(VCPKG_MESON_CROSS_FILE "${MESON_CROSS}")
VCEOF

INFO "Toolchain cmake:"
awk '{print "    "$0}' "${TOOLCHAIN_CMAKE}"
INFO "VCPKG triplet (mipsel-linux):"
awk '{print "    "$0}' "${VCPKG_ROOT}/custom-triplets/mipsel-linux.cmake"

# ── Step 7: Dependency overlay ports ─────────────────────────────────────────
STEP "Create Dependency Overlay Ports"

# protobuf: force protobuf_HAVE_BUILTIN_ATOMICS=ON
# GCC 8.4.0 mipsel cross-compile fails the cmake try_compile atomics test,
# which triggers a hardcoded target_link_libraries(libprotobuf ...) bug in
# protobuf-configure-target.cmake that cmake 4.x rejects.
mkdir -p "${VCPKG_OVERLAYS}/ports/protobuf"
cp -r "${VCPKG_ROOT}/ports/protobuf/." "${VCPKG_OVERLAYS}/ports/protobuf/"
# Patch 1: force HAVE_BUILTIN_ATOMICS=ON to avoid cmake 4.x target_link_libraries
#           ordering bug triggered by the cross-compile try_compile failure
sed -i 's/-Dprotobuf_BUILD_TESTS=OFF/-Dprotobuf_BUILD_TESTS=OFF\n        -Dprotobuf_HAVE_BUILTIN_ATOMICS=ON/' \
    "${VCPKG_OVERLAYS}/ports/protobuf/portfile.cmake"
grep -q "HAVE_BUILTIN_ATOMICS" "${VCPKG_OVERLAYS}/ports/protobuf/portfile.cmake" \
    || { INFO "ERROR: protobuf atomic patch failed"; GTE ${ZT_STEP}; }
# Patch 2: disable libprotoc/libupb when cross-compiling — they produce host
#           code-generation tools that must not be built for the mipsel target
sed -i 's/if(VCPKG_TARGET_IS_UWP)/if(VCPKG_TARGET_IS_UWP OR NOT protobuf_BUILD_PROTOC_BINARIES)/' \
    "${VCPKG_OVERLAYS}/ports/protobuf/portfile.cmake"
grep -q "NOT protobuf_BUILD_PROTOC_BINARIES" "${VCPKG_OVERLAYS}/ports/protobuf/portfile.cmake" \
    || { INFO "ERROR: protobuf libprotoc cross-compile patch failed"; GTE ${ZT_STEP}; }
INFO "protobuf overlay: HAVE_BUILTIN_ATOMICS=ON + libprotoc/libupb disabled for cross-compile."

# openssl: inject no-asm for MIPS musl (prevents SIGBUS on TLS handshake)
mkdir -p "${VCPKG_OVERLAYS}/ports/openssl"
cp -r "${VCPKG_ROOT}/ports/openssl/." "${VCPKG_OVERLAYS}/ports/openssl/"

if grep -rl "no-tests" "${VCPKG_OVERLAYS}/ports/openssl/" &>/dev/null; then
    grep -rl "no-tests" "${VCPKG_OVERLAYS}/ports/openssl/" \
        | xargs sed -i 's/\bno-tests\b/no-asm no-tests/g'
    INFO "Patched: no-asm injected before no-tests"
else
    INFO "WARNING: 'no-tests' token not found — scanning for Configure invocations"
    find "${VCPKG_OVERLAYS}/ports/openssl" -name "*.cmake" \
        | xargs grep -l "Configure" 2>/dev/null \
        | xargs sed -i 's/"Configure"/"Configure"\n        "no-asm"/g' 2>/dev/null || true
fi

grep -rq "no-asm" "${VCPKG_OVERLAYS}/ports/openssl/" \
    || { INFO "ERROR: no-asm injection failed — manual fix required"; GTE ${ZT_STEP}; }
INFO "Overlay port verified (no-asm present)."

# pcap headers — pcap is dlopen'd at runtime; only headers needed for cross-compile type defs.
# Inject into VCPKG install root (already an -isystem path) so no cmake flag changes needed.
PCAP_EXTRACT_DIR="${ZT_ROOT}/pcap-extract"
if dpkg-query -W -f='${Status}' libpcap-dev 2>/dev/null | grep -q "^install ok installed"; then
    PCAP_HEADERS_SRC="/usr/include"
    INFO "libpcap-dev installed — will use system pcap headers."
else
    INFO "libpcap-dev not installed — downloading headers via apt-get download (no sudo)..."
    mkdir -p "${PCAP_EXTRACT_DIR}"
    # libpcap-dev is a transitional package; actual headers are in libpcap0.8-dev
    (cd "${PCAP_EXTRACT_DIR}" && apt-get download libpcap0.8-dev 2>&1) \
        || { INFO "ERROR: apt-get download libpcap0.8-dev failed"; GTE ${ZT_STEP}; }
    PCAP_DEB=$(ls "${PCAP_EXTRACT_DIR}"/libpcap0.8-dev_*.deb 2>/dev/null | head -1)
    [[ -f "${PCAP_DEB}" ]] \
        || { INFO "ERROR: libpcap0.8-dev .deb not found"; GTE ${ZT_STEP}; }
    dpkg-deb -x "${PCAP_DEB}" "${PCAP_EXTRACT_DIR}" \
        || { INFO "ERROR: dpkg-deb extract failed"; GTE ${ZT_STEP}; }
    PCAP_HEADERS_SRC="${PCAP_EXTRACT_DIR}/usr/include"
    INFO "pcap headers extracted to ${PCAP_HEADERS_SRC}"
fi

# ── Step 8: VCPKG install dependencies ───────────────────────────────────────
STEP "VCPKG Install Dependencies (mipsel-linux)"
VCPKG_COMMON_OPTS=(
    "--x-install-root=${VCPKG_INSTALL_ROOT}"
    "--triplet" "mipsel-linux"
    "--overlay-triplets=${VCPKG_ROOT}/custom-triplets"
    "--overlay-ports=${VCPKG_OVERLAYS}/ports"
)

INFO "Installing from manifest (vcpkg.json)..."
"${VCPKG_ROOT}/vcpkg" install \
    "${VCPKG_COMMON_OPTS[@]}" \
    --x-manifest-root="${ZT_SDKDIR}" \
    || GTE ${ZT_STEP}

INFO "Installing openssl (no-asm overlay)..."
"${VCPKG_ROOT}/vcpkg" install openssl \
    "${VCPKG_COMMON_OPTS[@]}" \
    || GTE ${ZT_STEP}

# Inject pcap headers into VCPKG install root — it's already an -isystem path in the build
INFO "Injecting pcap headers into VCPKG install include path..."
mkdir -p "${VCPKG_INSTALL_ROOT}/mipsel-linux/include"
cp -rn "${PCAP_HEADERS_SRC}/pcap" "${VCPKG_INSTALL_ROOT}/mipsel-linux/include/" 2>/dev/null || true
[[ -f "${PCAP_HEADERS_SRC}/pcap.h" ]] && \
    cp -n "${PCAP_HEADERS_SRC}/pcap.h" "${VCPKG_INSTALL_ROOT}/mipsel-linux/include/" 2>/dev/null || true
[[ -d "${VCPKG_INSTALL_ROOT}/mipsel-linux/include/pcap" ]] \
    || { INFO "ERROR: pcap headers not found in ${PCAP_HEADERS_SRC}"; GTE ${ZT_STEP}; }
INFO "pcap headers injected into ${VCPKG_INSTALL_ROOT}/mipsel-linux/include/"

# ── Step 9: Patch CMakePresets.json for ci-linux-mipsel ──────────────────────
STEP "Patch CMakePresets.json (inject ci-linux-mipsel)"
jq 'if any(.configurePresets[]; .name == "ci-linux-mipsel")
    then .
    else .configurePresets += [{
        "name": "ci-linux-mipsel",
        "inherits": "ci-linux-x64",
        "cacheVariables": {
            "VCPKG_TARGET_TRIPLET": "mipsel-linux",
            "VCPKG_CHAINLOAD_TOOLCHAIN_FILE": "${sourceDir}/toolchains/mipsel-openwrt.cmake"
        }
    }] end' \
    "${ZT_SDKDIR}/CMakePresets.json" > "${ZT_SDKDIR}/CMakePresets_NEW.json" \
    && mv -f "${ZT_SDKDIR}/CMakePresets_NEW.json" "${ZT_SDKDIR}/CMakePresets.json" \
    || GTE ${ZT_STEP}
INFO "ci-linux-mipsel preset injected."

# ── Step 10: CMake configure ──────────────────────────────────────────────────
STEP "CMake Configure (preset: ci-linux-mipsel)"
cmake_config_opts=(
    "--preset" "ci-linux-mipsel"
    "-DDISABLE_LIBSYSTEMD_FEATURE=ON"
    "-DHAVE_LIBSODIUM=ON"
    "-DTLSUV_TLSLIB=openssl"
    "-DCMAKE_PREFIX_PATH=${VCPKG_INSTALL_ROOT}/mipsel-linux"
    "-DCMAKE_TOOLCHAIN_FILE=${TOOLCHAIN_CMAKE}"
    "-DGIT_VERSION=${ZT_TUNVER}-0-0"
    "-S" "${ZT_SDKDIR}"
    "-B" "${ZT_SDKDIR}/build"
)
[[ -x "/usr/bin/ninja" ]] && cmake_config_opts+=("-G" "Ninja")
INFO "cmake ${cmake_config_opts[*]}"
cmake "${cmake_config_opts[@]}" || GTE ${ZT_STEP}

# ── Step 11: Pre-build modifications ─────────────────────────────────────────
STEP "Pre-Build Modifications"
# Welcome banner
sed -i '/Ziti C SDK version/i ZITI_LOG(INFO, "Welcome to Ziti - OpenWRT RUT956 Edition [v'"${ZT_TUNVER}"']");' \
    "${ZT_SDKDIR}/build/_deps/ziti-sdk-c-src/library/utils.c" 2>/dev/null || true
# GCC 4.9 prereq check in metrics.h breaks with GCC 8 on pre-0.21.6 SDK sources
find "${ZT_SDKDIR}" -name "metrics.h" \
    | xargs sed -i '/# if ! __GNUC_PREREQ(4,9)/,+2d' 2>/dev/null || true
INFO "Pre-build mods applied."

# ── Step 12: Build ────────────────────────────────────────────────────────────
STEP "Build ziti-edge-tunnel"
cmake --build "${ZT_SDKDIR}/build" --target ziti-edge-tunnel || GTE ${ZT_STEP}

# ── Step 13: Compress output ──────────────────────────────────────────────────
STEP "Compress Output"
ZT_BINARY="${ZT_SDKDIR}/build/programs/ziti-edge-tunnel/ziti-edge-tunnel"
OUTPUT_GZ="${ZT_WORKDIR}/OpenWRT-RUT956-${ZT_TUNVER}.gz"
[[ -f "${ZT_BINARY}" ]] \
    || { INFO "ERROR: Binary not found at ${ZT_BINARY}"; GTE ${ZT_STEP}; }
gzip -ck9 "${ZT_BINARY}" > "${OUTPUT_GZ}" || GTE ${ZT_STEP}
INFO "Output : ${OUTPUT_GZ}"
INFO "Size   : $(du -h "${OUTPUT_GZ}" | cut -f1) compressed / $(du -h "${ZT_BINARY}" | cut -f1) raw"
INFO "Type   : $(file "${ZT_BINARY}")"

# ── Step 14: Cleanup ──────────────────────────────────────────────────────────
STEP "Cleanup Staging Area"
chmod -R u+w "${ZT_ROOT}" 2>/dev/null || true
rm -rf "${ZT_ROOT}"

printf '\n\e[1;42m Build complete: %s \e[0m\n' "${OUTPUT_GZ}"
