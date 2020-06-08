#!/bin/bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

source "bazel.sh"

"${bazel}" build :compdb

if [[ "$(uname -s)" == "Darwin" ]]; then
  expected="expected_macos.json"
  expected_ycm="expected_ycm_macos.json"
else
  expected="expected_ubuntu.json"
  expected_ycm="expected_ycm_ubuntu.json"
fi

diff "${expected}" bazel-bin/compile_commands.json

diff \
  <(sed -e "s@EXECROOT@$(bazel info execution_root)@" -e "s@PWD@${PWD}@" "${expected_ycm}") \
  <(python ../.ycm_extra_conf.py a.cc)
