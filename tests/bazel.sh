# Use bazelisk to catch migration problems.
if command -v bazelisk >/dev/null; then
  # bazelisk is installed on Github Actions VMs.
  bazel="$(command -v bazelisk)"
  readonly bazel
else
  os="$(uname -s | tr "[:upper:]" "[:lower:]")"
  readonly os

  # Fetch bazelisk on user machines.
  readonly url="https://github.com/bazelbuild/bazelisk/releases/download/v1.4.0/bazelisk-${os}-amd64"
  readonly bin_dir="${TMPDIR:-/tmp}/bin"
  readonly bazel="${bin_dir}/bazel"

  mkdir -p "${bin_dir}"
  export PATH="${bin_dir}:${PATH}"
  curl -L -sSf -o "${bazel}" "${url}"
  chmod a+x "${bazel}"
fi
