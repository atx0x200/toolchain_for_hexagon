#!/bin/bash

#  Copyright (c) 2021, Qualcomm Innovation Center, Inc. All rights reserved.
#  SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

SRC_DIR=${1}
MANIFEST_DIR=${2}

echo Cloning repos into "${SRC_DIR}":
git clone --branch llvmorg-${VER} --depth 1 https://llvm.googlesource.com/llvm-project
git clone --depth=1 -q https://github.com/llvm/llvm-test-suite &
git clone --depth=1 -q https://github.com/atx0x200/RubikPi-HexagonLinux.git &
git clone --depth=1 -q https://github.com/python/cpython &
git clone --depth=1 -q git://repo.or.cz/libc-test &
git clone -q https://git.busybox.net/busybox/ &
git clone -q https://github.com/atx0x200/buildroot.git
git clone -q https://github.com/atx0x200/musl.git

wait
git clone --branch release/22.x --depth 1 https://github.com/qualcomm/eld/ llvm-project/eld/
ln -s RubikPi-HexagonLinux/hexagon linux

dump_checkout_info() {
	out=${1}
	mkdir -p ${out}
	for d in ./*
	do
		if [[ -d ${d} ]]; then
			proj=$(basename ${d})
			cd ${d}
			git remote -v > ${out}/${proj}.txt
			git log -3 HEAD >> ${out}/${proj}.txt
			cd -
		fi
	done
}

mkdir -p ${MANIFEST_DIR}
dump_checkout_info ${MANIFEST_DIR}

apply_patches() {
	local repo_name=$1
	local tag_name=$2
	local patch_dir=${SRC_DIR}/patches/${repo_name}/${tag_name}
	if compgen -G "${patch_dir}/*.patch" > /dev/null 2>&1; then
		echo "Applying patches from ${patch_dir}"
		for p in "${patch_dir}"/*.patch; do
			echo "  Applying $(basename "$p")"
			patch -p1 < "$p"
		done
	fi
}
cd llvm-project
apply_patches llvm-project llvmorg-${VER}

cat <<EOF
Now that you've cloned the source repos, refer to Dockerfile to find the git refs
of each repo that should be checked out to build a known good configuration.
EOF
