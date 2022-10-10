# Copyright 2022 Aqrose Technology, Ltd.
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

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

_cuda_config = """
load("@rules_cuda//cuda:deps.bzl", _register_detected_cuda_toolchains = "register_detected_cuda_toolchains", _rules_cuda_deps = "rules_cuda_deps")
load("@rules_cuda//cuda/private:toolchain.bzl", _find_cuda_toolchain = "find_cuda_toolchain", _use_cuda_toolchain = "use_cuda_toolchain")
load("@rules_cuda//cuda/private:rules/common.bzl", _ALLOW_CUDA_HDRS = "ALLOW_CUDA_HDRS", _ALLOW_CUDA_SRCS = "ALLOW_CUDA_SRCS")
load("@rules_cuda//cuda/private:cuda_helper.bzl", _cuda_helper = "cuda_helper", )
load("@bazel_skylib//lib:paths.bzl", _paths = "paths")
load("@bazel_skylib//rules:common_settings.bzl", _BuildSettingInfo = "BuildSettingInfo")
load("@rules_cuda//cuda/private:providers.bzl", _CudaArchsInfo = "CudaArchsInfo", _CudaInfo = "CudaInfo")
load("@rules_cuda//cuda/private:action_names.bzl", _ACTION_NAMES = "ACTION_NAMES")
load("@rules_cuda//cuda/private:toolchain_config_lib.bzl", _config_helper = "config_helper", _unique = "unique")
load("@rules_cuda//cuda/private:rules/cuda_toolkit.bzl", _cuda_toolkit = "cuda_toolkit")
register_detected_cuda_toolchains = _register_detected_cuda_toolchains
rules_cuda_deps = _rules_cuda_deps
find_cuda_toolchain = _find_cuda_toolchain
use_cuda_toolchain = "@rules_cuda" + ''.join(_use_cuda_toolchain())
ALLOW_CUDA_HDRS = _ALLOW_CUDA_HDRS
ALLOW_CUDA_SRCS = _ALLOW_CUDA_SRCS
cuda_helper = _cuda_helper
paths = _paths
BuildSettingInfo = _BuildSettingInfo
CudaArchsInfo = _CudaArchsInfo
CudaInfo = _CudaInfo
ACTION_NAMES = _ACTION_NAMES
unique = _unique
config_helper = _config_helper
cuda_toolkit = _cuda_toolkit
"""

_empty_config = """
register_detected_cuda_toolchains = ""
rules_cuda_deps = ""
find_cuda_toolchain = ""
use_cuda_toolchain = ""
ALLOW_CUDA_HDRS = ""
ALLOW_CUDA_SRCS = ""
cuda_helper = ""
paths = ""
BuildSettingInfo = ""
CudaArchsInfo = ""
CudaInfo = ""
ACTION_NAMES = ""
unique = ""
config_helper = ""
cuda_toolkit = ""
"""

def _config_compdb_repository_impl(rctx):
    build_file_content = ""

    if rctx.attr.cuda_enable:
        build_file_content += _cuda_config
    else:
        build_file_content += _empty_config

    build_file_content += "global_filter_flags = %s\ncuda_enable = %s\n" % (rctx.attr.global_filter_flags, rctx.attr.cuda_enable)

    cuda_path = ""

    if rctx.attr.cuda_enable:
        cuda_path = rctx.os.environ.get("CUDA_PATH", None)
        if cuda_path == None:
            ptxas_path = rctx.which("ptxas")
            if ptxas_path:
                # ${CUDA_PATH}/bin/ptxas
                cuda_path = str(ptxas_path.dirname.dirname)
        if cuda_path == None and rctx.os.name.startswith("linux"):
            cuda_path = "/usr/local/cuda"

        if cuda_path != None and not rctx.path(cuda_path).exists:
            cuda_path = None

        if rctx.os.name.lower().startswith("windows"):
            cuda_path = cuda_path.replace("\\", "/")
            mklink_cuda_path = rctx.execute(["cmd", "/c", "echo", "%USERPROFILE%\\AppData\\Local\\CUDA_PATH"]).stdout
            mklink_cuda_path = mklink_cuda_path[:-2]
            rctx.execute(["cmd", "/c", "if", "exist", mklink_cuda_path, "(", "rd", "/s", "/q", mklink_cuda_path, ")"])
            res = rctx.execute(["cmd", "/c", "mklink", "/J", mklink_cuda_path, cuda_path])
            if res.return_code != 0:
                fail("windows mklink CUDA_PATH failed (%d): %s" % (res.return_code, res.stderr))
            mklink_cuda_path = mklink_cuda_path.replace("\\", "/")
            cuda_path = mklink_cuda_path

    build_file_content += "cuda_path = '%s'\n" % cuda_path

    rctx.file("BUILD.bazel", "")
    rctx.file("config.bzl", build_file_content)

config_compdb_repository = repository_rule(
    implementation = _config_compdb_repository_impl,
    local = True,
    attrs = {
        "global_filter_flags": attr.string_list(
            default = [
                "-isysroot __BAZEL_XCODE_SDKROOT__",
            ],
            doc = "Filter the flags in the compilation command that clang does not support.",
        ),
        "cuda_enable": attr.bool(
            default = False,
            doc = "Enable the cuda compiler.",
        ),
    },
    doc = "To config compdb.",
)

def config_compdb(**kwargs):
    cuda_enable = kwargs.pop("cuda_enable", False)
    if cuda_enable:
        maybe(
            name = "bazel_skylib",
            repo_rule = http_archive,
            sha256 = "d847b08d6702d2779e9eb399b54ff8920fa7521dc45e3e53572d1d8907767de7",
            strip_prefix = "bazel-skylib-2a87d4a62af886fb320883aba102255aba87275e",
            urls = ["https://github.com/bazelbuild/bazel-skylib/archive/2a87d4a62af886fb320883aba102255aba87275e.tar.gz"],
        )

        maybe(
            name = "rules_cuda",
            repo_rule = http_archive,
            sha256 = "a10a7efbf886a42f5c849dd515c22b72a58d37fdd8ee1436327c47f525e70f26",
            strip_prefix = "rules_cuda-19f91525682511a2825037e3ac568cba22329733",
            urls = ["https://github.com/cloudhan/rules_cuda/archive/19f91525682511a2825037e3ac568cba22329733.zip"],
        )

    config_compdb_repository(name = "com_grail_bazel_config_compdb", cuda_enable = cuda_enable, **kwargs)
