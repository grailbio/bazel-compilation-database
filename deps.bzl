# Copyright 2021-2022 GRAIL, Inc.
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

load("@com_grail_bazel_compdb//:tools.bzl", "setup_tools")
load("@com_grail_bazel_config_compdb//:config.bzl", "cuda_enable", "register_detected_cuda_toolchains", "rules_cuda_deps")

def bazel_compdb_deps():
    setup_tools()

    if cuda_enable:
        rules_cuda_deps()
        register_detected_cuda_toolchains()
