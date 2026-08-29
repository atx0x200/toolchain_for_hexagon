#!/bin/bash -x

#  Copyright (c) 2026, Qualcomm Innovation Center, Inc. All rights reserved.
#  SPDX-License-Identifier: BSD-3-Clause
#
# Builds a "Canadian cross" Hexagon Linux toolchain: a clang/lld that
# itself RUNS on hexagon-unknown-linux-musl (i.e. natively on the Hexagon
# core once it's booted Linux), rather than on the machine doing this
# build.
#
#   build  = whatever machine runs this script (aarch64-linux-gnu here)
#   host   = hexagon-unknown-linux-musl  (where the produced clang/lld run)
#   target = hexagon-unknown-linux-musl  (what the produced clang/lld emit)
#
# This reuses two things build-toolchain.sh already produced:
#   1. clang+llvm-main/${BOOTSTRAP_HOST_TRIPLE}/bin/hexagon-unknown-linux-musl-clang{,++}
#      -- a working hexagon-unknown-linux-musl cross-compiler that itself
#      runs on ${BOOTSTRAP_HOST_TRIPLE}. Used as CC/CXX to compile this new
#      LLVM/clang so the *output* binaries are hexagon-unknown-linux-musl
#      instead of ${BOOTSTRAP_HOST_TRIPLE}.
#   2. obj_llvm/bin/{llvm,clang}-tblgen -- native tblgen binaries built for
#      *this* build machine, passed via LLVM_NATIVE_TOOL_DIR so the cross
#      build doesn't need to build (or run, via qemu) a hexagon tblgen.
#
# It does NOT rebuild musl/compiler-rt/libc++/libc++abi/libunwind for
# hexagon-unknown-linux-musl -- those are triple-specific, not
# host-machine-specific, and are already sitting in the bootstrap
# compiler's target/hexagon-unknown-linux-musl sysroot. That sysroot is
# copied into the new install tree unchanged.
#
# See llvm-project/clang/cmake/caches/hexagon-unknown-linux-musl-clang-canadian.cmake
# for the cmake side of this.
#
# ENABLE_DYLIB=1: link clang/lld against a shared libLLVM.so (+
# libclang-cpp.so) instead of statically linking everything into each
# binary. A statically-linked clang here runs 130+ MB; most of that is
# LLVM/clang code duplicated into every tool that uses it. Building it
# once as a shared library and having clang/ld.lld link against it
# dynamically cuts the on-device footprint substantially. See
# llvm-project/clang/cmake/caches/hexagon-unknown-linux-musl-clang-canadian-dylib.cmake.
#
# lldb-server: WIRED UP BUT OFF BY DEFAULT. lldb-server's Linux ptrace
# backend has no Hexagon register-context implementation (upstream or in
# this fork), so building it currently fails to link. Set
# ENABLE_LLDB_SERVER=1 to attempt it anyway (e.g. once that backend has
# been implemented) -- see
# llvm-project/lldb/cmake/caches/hexagon-lldb-server-canadian.cmake for
# the full explanation.

set -euo pipefail
set -x

BASE=$(readlink -f "$(dirname "$0")")

# Where build-toolchain.sh installed the existing triples
# (clang+llvm-main/aarch64-linux-gnu, .../hexagon-unknown-none-elf, etc).
TOOLCHAIN_INSTALL=$(readlink -f "${TOOLCHAIN_INSTALL:-${BASE}/clang+llvm-main}")

# Host of the already-built hexagon-unknown-linux-musl bootstrap compiler
# used as CC/CXX for this build. Must be a triple this build machine can
# actually execute binaries for (no emulation is set up here).
BOOTSTRAP_HOST_TRIPLE=${BOOTSTRAP_HOST_TRIPLE:-aarch64-linux-gnu}
BOOTSTRAP_BIN=${TOOLCHAIN_INSTALL}/${BOOTSTRAP_HOST_TRIPLE}/bin
HEX_SYSROOT_SRC=${TOOLCHAIN_INSTALL}/${BOOTSTRAP_HOST_TRIPLE}/target/hexagon-unknown-linux-musl

# Native tblgen tools built for *this* build machine (from the ordinary
# build_llvm_clang stage0 build in build-toolchain.sh).
NATIVE_TOOL_DIR=$(readlink -f "${NATIVE_TOOL_DIR:-${BASE}/obj_llvm/bin}")

HEX_TRIPLE=hexagon-unknown-linux-musl
CANADIAN_INSTALL=${TOOLCHAIN_INSTALL}/${HEX_TRIPLE}
CANADIAN_BIN=${CANADIAN_INSTALL}/bin
OBJ_DIR=${BASE}/obj_llvm_canadian_${HEX_TRIPLE}

ENABLE_LLDB_SERVER=${ENABLE_LLDB_SERVER:-0}
ENABLE_DYLIB=${ENABLE_DYLIB:-0}

check_prereqs() {
	if [[ ! -x ${BOOTSTRAP_BIN}/hexagon-unknown-linux-musl-clang ]]; then
		echo "err: ${BOOTSTRAP_BIN}/hexagon-unknown-linux-musl-clang not found." >&2
		echo "     Run build-toolchain.sh first (or set BOOTSTRAP_HOST_TRIPLE" >&2
		echo "     / TOOLCHAIN_INSTALL to point at an existing build)." >&2
		exit 1
	fi
	if ! "${BOOTSTRAP_BIN}/hexagon-unknown-linux-musl-clang" --version >/dev/null 2>&1; then
		echo "err: ${BOOTSTRAP_BIN}/hexagon-unknown-linux-musl-clang exists but" >&2
		echo "     can't execute on this machine (wrong host arch for" >&2
		echo "     BOOTSTRAP_HOST_TRIPLE=${BOOTSTRAP_HOST_TRIPLE}?)." >&2
		exit 1
	fi
	if [[ ! -x ${NATIVE_TOOL_DIR}/llvm-tblgen || ! -x ${NATIVE_TOOL_DIR}/clang-tblgen ]]; then
		echo "err: llvm-tblgen/clang-tblgen not found in ${NATIVE_TOOL_DIR}." >&2
		echo "     Run build-toolchain.sh first to produce a native obj_llvm" >&2
		echo "     build (or set NATIVE_TOOL_DIR)." >&2
		exit 1
	fi
	if [[ ! -d ${HEX_SYSROOT_SRC} ]]; then
		echo "err: hexagon-unknown-linux-musl sysroot not found at" >&2
		echo "     ${HEX_SYSROOT_SRC}" >&2
		exit 1
	fi
}

add_symlinks() {
	linkdir=${1}

	for triple in hexagon-unknown-linux-musl hexagon-unknown-none-elf hexagon-unknown-qurt hexagon-linux-musl hexagon-none-elf hexagon-qurt hexagon
	do
		ln -sf --relative "${linkdir}"/llvm-size "${linkdir}"/${triple}-size
		ln -sf --relative "${linkdir}"/llvm-strip "${linkdir}"/${triple}-strip
		ln -sf --relative "${linkdir}"/llvm-nm "${linkdir}"/${triple}-nm
		ln -sf --relative "${linkdir}"/llvm-ar "${linkdir}"/${triple}-ar
		ln -sf --relative "${linkdir}"/llvm-objdump "${linkdir}"/${triple}-objdump
		ln -sf --relative "${linkdir}"/llvm-objcopy "${linkdir}"/${triple}-objcopy
		ln -sf --relative "${linkdir}"/llvm-readelf "${linkdir}"/${triple}-readelf
		ln -sf --relative "${linkdir}"/llvm-ranlib "${linkdir}"/${triple}-ranlib
		ln -sf --relative "${linkdir}"/llvm-config "${linkdir}"/${triple}-llvm-config
		ln -sf --relative "${linkdir}"/ld.lld "${linkdir}"/${triple}-ld.lld
	done

	for triple in hexagon-unknown-linux-musl hexagon-unknown-none-elf hexagon-unknown-qurt hexagon-linux-musl hexagon-none-elf hexagon-qurt hexagon
	do
		ln -sf --relative "${linkdir}"/clang "${linkdir}"/${triple}-clang
		ln -sf --relative "${linkdir}"/clang "${linkdir}"/${triple}-clang++
		ln -sf --relative "${linkdir}"/clang "${linkdir}"/${triple}-cc
	done
}

add_multilib_symlinks() {
	linkdir=${1}

	cd "${linkdir}"
	for arch in v68 v69 v71 v73 v75 v79
	do
		ln -sf --relative ../usr/lib ./${arch}
	done
	cd -
}

build_canadian_clang() {
	cd "${BASE}"

	if [[ "${IN_CONTAINER-0}" -ne 1 ]]; then
		CMAKE_CCACHE="-DLLVM_CCACHE_BUILD:BOOL=ON"
	fi
	if [[ -n "${LLVM_PARALLEL_LINK_JOBS-}" ]]; then
		CMAKE_LINK_JOBS="-DLLVM_PARALLEL_LINK_JOBS=${LLVM_PARALLEL_LINK_JOBS}"
	fi

	LLDB_CACHE=""
	if [[ "${ENABLE_LLDB_SERVER}" -eq 1 ]]; then
		LLDB_CACHE="-C ./llvm-project/lldb/cmake/caches/hexagon-lldb-server-canadian.cmake"
		echo "=================================================================="
		echo " ENABLE_LLDB_SERVER=1: attempting lldb-server."
		echo " This is expected to FAIL TO LINK -- lldb-server has no Hexagon"
		echo " ptrace backend upstream or in this fork. See"
		echo " llvm-project/lldb/cmake/caches/hexagon-lldb-server-canadian.cmake"
		echo " for the full explanation and what a fix requires."
		echo "=================================================================="
	fi

	# Same component list as hexagon-unknown-linux-musl-clang-canadian.cmake's
	# own LLVM_DISTRIBUTION_COMPONENTS default; kept here too (rather than
	# just relying on the cache file) so ENABLE_DYLIB can append the
	# LLVM/clang-cpp shared-library components -- matching how
	# build_llvm_clang_cross in build-toolchain.sh does it for its own
	# zig dylib cross-builds.
	DIST_COMPONENTS=(
		clang clang-resource-headers lld
		llvm-addr2line llvm-ar llvm-config llvm-cov llvm-cxxfilt llvm-dwarfdump
		llvm-mc llvm-nm llvm-objcopy llvm-objdump llvm-profdata
		llvm-ranlib llvm-readelf llvm-readobj
		llvm-size llvm-strings llvm-strip llvm-symbolizer
	)
	DYLIB_CACHE=""
	if [[ "${ENABLE_DYLIB}" -eq 1 ]]; then
		DYLIB_CACHE="-C ./llvm-project/clang/cmake/caches/hexagon-unknown-linux-musl-clang-canadian-dylib.cmake"
		DIST_COMPONENTS+=(LLVM clang-cpp)
	fi
	DIST_LIST=$(IFS=';'; echo "${DIST_COMPONENTS[*]}")

	CC=${BOOTSTRAP_BIN}/hexagon-unknown-linux-musl-clang \
	CXX=${BOOTSTRAP_BIN}/hexagon-unknown-linux-musl-clang++ \
		cmake -G Ninja \
		-DCMAKE_INSTALL_PREFIX:PATH="${CANADIAN_INSTALL}"/ \
		${CMAKE_CCACHE-} \
		${CMAKE_LINK_JOBS-} \
		-DLLVM_ENABLE_ASSERTIONS:BOOL=ON \
		-DLLVM_HOST_TRIPLE=${HEX_TRIPLE} \
		-DLLVM_NATIVE_TOOL_DIR="${NATIVE_TOOL_DIR}" \
		-DCMAKE_BUILD_WITH_INSTALL_RPATH:BOOL=ON \
		-DCMAKE_CROSSCOMPILING:BOOL=ON \
		-C ./llvm-project/clang/cmake/caches/hexagon-unknown-linux-musl-clang-canadian.cmake \
		${DYLIB_CACHE} \
		${LLDB_CACHE} \
		-DLLVM_DISTRIBUTION_COMPONENTS="${DIST_LIST}" \
		-B "${OBJ_DIR}" \
		-S ./llvm-project/llvm
	cmake --build "${OBJ_DIR}" --target install-distribution

	if [[ "${ENABLE_LLDB_SERVER}" -eq 1 ]]; then
		cmake --build "${OBJ_DIR}" --target lldb-server
		install -m 0755 "${OBJ_DIR}"/bin/lldb-server "${CANADIAN_BIN}"/lldb-server
	fi

	if [[ "${IN_CONTAINER-0}" -eq 1 ]]; then
		rm -rf "${OBJ_DIR}"
	fi
}

install_canadian_sysroot() {
	# musl / libc++ / libc++abi / libunwind / compiler-rt for
	# hexagon-unknown-linux-musl are triple-specific, not
	# host-machine-specific -- reuse the ones already built by
	# build-toolchain.sh instead of rebuilding them here.
	rm -rf "${CANADIAN_INSTALL}"/target
	mkdir -p "${CANADIAN_INSTALL}"/target
	cp -ra "${HEX_SYSROOT_SRC}" "${CANADIAN_INSTALL}"/target/${HEX_TRIPLE}

	cd "${CANADIAN_INSTALL}"/target
	ln -sf ${HEX_TRIPLE} hexagon
	ln -sf ${HEX_TRIPLE} hexagon-linux-musl

	DEST_TGT_LIB=${CANADIAN_INSTALL}/target/${HEX_TRIPLE}/lib
	mkdir -p "${DEST_TGT_LIB}"
	add_multilib_symlinks "${DEST_TGT_LIB}"

	cp "${BASE}"/hexagon-unknown-none-elf.cfg "${CANADIAN_BIN}"/hexagon-unknown-none-elf.cfg
	ln -sf hexagon-unknown-none-elf.cfg "${CANADIAN_BIN}"/hexagon.cfg
}

check_prereqs

which ninja
ninja --version
which cmake
cmake --version

build_canadian_clang
add_symlinks "${CANADIAN_BIN}"
install_canadian_sysroot

echo "Canadian toolchain installed to ${CANADIAN_INSTALL}"
echo "This clang/lld runs ON hexagon-unknown-linux-musl and targets"
echo "hexagon-unknown-linux-musl -- copy ${CANADIAN_INSTALL} to the device"
echo "to use it there. It will not run on ${BOOTSTRAP_HOST_TRIPLE}."
if [[ "${ENABLE_DYLIB}" -eq 1 ]]; then
	echo "Built with ENABLE_DYLIB=1: clang/ld.lld link against"
	echo "${CANADIAN_BIN}/../lib/libLLVM.so and libclang-cpp.so -- both must"
	echo "ship alongside bin/ on the device (already true if you copy"
	echo "${CANADIAN_INSTALL} as a whole)."
fi
