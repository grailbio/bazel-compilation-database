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

load(":aspects.bzl", "compilation_database_aspect")

_clang_tidy_script = """\
#!/bin/bash

pwd
cmd="ln -sf {compdb_file} compile_commands.json"
echo $cmd
eval $cmd

cmd="clang-tidy {options} $@ {sources}"
echo $cmd
eval $cmd
"""

def _clang_tidy_check_impl(ctx):
    compdb_file = ctx.attr.src[OutputGroupInfo].compdb_file.to_list()[0]
    src_files = ctx.attr.src[OutputGroupInfo].source_files.to_list()
    hdr_files = ctx.attr.src[OutputGroupInfo].header_files.to_list()

    if len(src_files) == 0:
        if ctx.attr.mandatory:
            fail("`src` must be a target with at least one source or header.")
        else:
            test_script = ctx.actions.declare_file(ctx.attr.name + ".sh")
            ctx.actions.write(output = test_script, content = "#noop", is_executable = True)

            return DefaultInfo(executable = test_script)


    sources = " ".join([ src.short_path for src in src_files ])
    build_path = compdb_file.dirname.replace(compdb_file.root.path + "/", "")
    options = " ".join(ctx.attr.options)
    content = _clang_tidy_script.format(
        compdb_file = compdb_file.short_path,
        build_path = build_path,
        sources = sources,
        options = options,
    )

    test_script = ctx.actions.declare_file(ctx.attr.name + ".sh")
    ctx.actions.write(output = test_script, content = content, is_executable = True)

    runfiles = src_files + hdr_files + [compdb_file]
    if ctx.attr.config != None:
        files = ctx.attr.config.files.to_list()
        if len(files) != 1:
            fail("`config` attribute in rule `clang_tidy_test` must be single file/target")
        runfiles.append(files[0])

    return DefaultInfo(
        files = depset([test_script, compdb_file]),
        runfiles = ctx.runfiles(files = runfiles),
        executable = test_script,
    )

clang_tidy_test = rule(
    attrs = {
        "src": attr.label(
            aspects = [compilation_database_aspect],
            doc = "Source target to run clang-tidy on.",
        ),
        "mandatory": attr.bool(
            default = False,
            doc = "Throw error if `src` is not eligible for linter check, e.g. have no C/C++ source or header.",
        ),
        "config": attr.label(
            doc = "Clang tidy configuration file",
            allow_single_file = True,
        ),
        "options": attr.string_list(
            doc = "options given to clang-tidy",
        )
    },
    test = True,
    implementation = _clang_tidy_check_impl,
)
