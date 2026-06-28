export ARTIFACT_TAG=main
export TOOLCHAIN_INSTALL=$PWD/clang+llvm-${ARTIFACT_TAG}
export ROOT_INSTALL=$PWD/install_rootfs
export ARTIFACT_BASE=$PWD/artifacts
export TEST_TOOLCHAIN=0
export CROSS_TRIPLES=""
export CROSS_TRIPLES_PIC=""
export CROSS_TRIPLES_DYLIB=""
mkdir -p ${ARTIFACT_BASE}
