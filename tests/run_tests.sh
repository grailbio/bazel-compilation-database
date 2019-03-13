#!/bin/bash

set -exuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

bazel build :compdb
diff expected_file.json bazel-bin/compile_commands.json

ln -s ../aspects.bzl .
cp ../.ycm_extra_conf.py .
diff expected_ycm_output.json <(python .ycm_extra_conf.py a.cc)
rm ./.ycm_extra_conf.py
rm ./aspects.bzl
