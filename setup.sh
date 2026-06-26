export ARTIFACT_TAG=22.1.8
export TOOLCHAIN_INSTALL=$PWD/clang+llvm-${ARTIFACT_TAG}-cross-hexagon-unknown-linux-musl
export ROOT_INSTALL=$PWD/install_rootfs
export ARTIFACT_BASE=$PWD/artifacts
export TEST_TOOLCHAIN=0
export CROSS_TRIPLES="aarch64-linux-gnu"
export CROSS_TRIPLES_PIC=""
export CROSS_TRIPLES_DYLIB=""
mkdir -p ${ARTIFACT_BASE}
