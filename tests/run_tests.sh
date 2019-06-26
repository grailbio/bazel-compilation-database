#!/bin/bash

set -exuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

os="$(uname -s | tr "[:upper:]" "[:lower:]")"
readonly os

# Use bazelisk to catch migration problems.
# Value of BAZELISK_GITHUB_TOKEN is set as a secret on Travis.
readonly url="https://github.com/bazelbuild/bazelisk/releases/download/v0.0.8/bazelisk-${os}-amd64"
readonly bin_dir="${TMPDIR:-/tmp}/bin"
readonly bazel="${bin_dir}/bazel"

mkdir -p "${bin_dir}"
export PATH="${bin_dir}:${PATH}"
curl -L -sSf -o "${bazel}" "${url}"
chmod a+x "${bazel}"

"${bazel}" --migrate build :compdb

diff expected_file.json bazel-bin/compile_commands.json

diff expected_ycm_output.json <(python ../.ycm_extra_conf.py a.cc)
