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

load("@rules_cuda//cuda:defs.bzl", "cuda_library")
load("@com_grail_bazel_compdb//:defs.bzl", "compilation_database")
load("@com_grail_bazel_output_base_util//:defs.bzl", "OUTPUT_BASE")

cuda_library(
    name = "example",
    srcs = ["example.cu"],
    hdrs = ["example.hpp"],
    copts = ["-G"],
    defines = [
        "USE_CUDA",
    ],
    host_defines = ["USE_TEST"],
    visibility = ["//:__pkg__"],
)

cc_library(
    name = "a",
    srcs = ["a.cc"],
    hdrs = ["a.h"],
    include_prefix = "dir_a",  # To test that we can work with _virtual_includes dirs.
)

cc_library(
    name = "b",
    srcs = ["b.cc"],
    deps = [":a"],
)

cc_library(
    name = "b_forward",
    deps = [":b"],
)

cc_binary(
    name = "stdlib",
    srcs = ["stdlib.cc"],
)

# For testing https://github.com/grailbio/bazel-compilation-database/issues/84.
filegroup(
    name = "b_filegrp",
    srcs = ["b"],
)

load("@com_grail_bazel_compdb//:defs.bzl", "compilation_database")
load("@com_grail_bazel_output_base_util//:defs.bzl", "OUTPUT_BASE")

compilation_database(
    name = "compdb",
    output_base = OUTPUT_BASE,
    targets = ["b_filegrp"],
)
