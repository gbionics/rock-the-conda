#!/bin/bash

set -xeuo pipefail

./configure \
    --prefix="${PREFIX}" \
    --libdir="${PREFIX}/lib" \
    --disable-silent-rules

make -j${CPU_COUNT}
make install