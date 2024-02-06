# Copyright 2024 The Bazel Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Use bazelisk to catch migration problems.
if command -v bazelisk >/dev/null; then
  # bazelisk is installed on Github Actions VMs.
  bazel="$(command -v bazelisk)"
  readonly bazel
else
  os="$(uname -s | tr "[:upper:]" "[:lower:]")"
  readonly os

  # Fetch bazelisk on user machines.
  readonly url="https://github.com/bazelbuild/bazelisk/releases/download/v1.5.0/bazelisk-${os}-amd64"
  readonly bin_dir="${TMPDIR:-/tmp}/bin"
  readonly bazel="${bin_dir}/bazel"

  mkdir -p "${bin_dir}"
  export PATH="${bin_dir}:${PATH}"
  curl -L -sSf -o "${bazel}" "${url}"
  chmod a+x "${bazel}"
fi
