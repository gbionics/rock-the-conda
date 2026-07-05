#!/bin/bash

set -xeuo pipefail

# Disable Python configuration for now, as the recipe only builds libotf2

export PYTHON=:
export PYTHON_FOR_GENERATOR=:
export SPHINX=:

./configure \
    --prefix="${PREFIX}" \
    --libdir="${PREFIX}/lib" \
    --disable-silent-rules \
    --enable-shared --disable-static

make -j${CPU_COUNT}
make install

# Remove unused docs
rm -rf ${PREFIX}/share/doc/otf2/
