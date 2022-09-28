# Copyright 2017-2022 GRAIL, Inc.
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

workspace(name = "com_grail_bazel_compdb")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@com_grail_bazel_compdb//:config.bzl", "config_compdb")

config_compdb(
    cuda_enable = True,
    global_filter_flags = [
        "-ccbin",
        "-gencode",
    ],
)

load("@com_grail_bazel_compdb//:deps.bzl", "bazel_compdb_deps")

bazel_compdb_deps()

http_archive(
    name = "rules_cuda",
    sha256 = "a10a7efbf886a42f5c849dd515c22b72a58d37fdd8ee1436327c47f525e70f26",
    strip_prefix = "rules_cuda-19f91525682511a2825037e3ac568cba22329733",
    urls = ["https://github.com/cloudhan/rules_cuda/archive/19f91525682511a2825037e3ac568cba22329733.zip"],
)

load("@rules_cuda//cuda:deps.bzl", "register_detected_cuda_toolchains", "rules_cuda_deps")

rules_cuda_deps()

register_detected_cuda_toolchains()
