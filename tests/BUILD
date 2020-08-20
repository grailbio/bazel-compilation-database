# Copyright 2017-2020 GRAIL, Inc.
# Copyright 2020 NVIDIA, Corp.
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

load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")

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

cc_binary(
    name = "stdlib",
    srcs = ["stdlib.cc"],
)

load("@compdb//:aspects.bzl", "compilation_database")

compilation_database(
    name = "compdb",
    targets = ["b"],
)

load("@compdb//:clang-tidy.bzl", "clang_tidy_test")

clang_tidy_test(
    name = "clang_tidy_test_a",
    src = ":a",
    config = "//:.clang-tidy",
)

clang_tidy_test(
    name = "clang_tidy_test_b",
    src = ":b",
    config = "//:.clang-tidy",
)

clang_tidy_test(
    name = "clang_tidy_test_stdlib",
    src = ":stdlib",
    config = "//:.clang-tidy",
)
