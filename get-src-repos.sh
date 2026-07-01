#!/bin/bash

#  Copyright (c) 2021, Qualcomm Innovation Center, Inc. All rights reserved.
#  SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

SRC_DIR=${1}
MANIFEST_DIR=${2}

echo Cloning repos into "${SRC_DIR}":
git clone --branch llvmorg-22.1.8 --depth 1 https://llvm.googlesource.com/llvm-project
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

cat <<EOF
Now that you've cloned the source repos, refer to Dockerfile to find the git refs
of each repo that should be checked out to build a known good configuration.
EOF
