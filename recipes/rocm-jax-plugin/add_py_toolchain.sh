#!/bin/bash
#
# Create a Python toolchain in the current working directory.

set -exuo pipefail

# Use the actual working directory (the Bazel workspace root) so that paths
# are correct even when build.sh has cd'd into a subdirectory of SRC_DIR.
WORKSPACE_DIR="$(pwd)"

mkdir -p py_toolchain
cp $RECIPE_DIR/py_toolchain.bzl py_toolchain/BUILD
sed -i "s;@@SRC_DIR@@;$WORKSPACE_DIR;" py_toolchain/BUILD

cat > python.shebang <<EOF
#!/bin/bash
export PYTHONSAFEPATH=1
${PYTHON} "\$@"
EOF
chmod +x python.shebang

cat >> .bazelrc <<EOF
build --extra_toolchains=//py_toolchain:py_toolchain
EOF
