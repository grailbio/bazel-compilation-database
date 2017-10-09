# Copyright 2017 GRAIL, Inc.
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

"""Compilation database generation Bazel rules.

compilation_database will generate a compile_commands.json file for the
given targets. This approach uses the aspects feature of bazel.

An alternative approach is the one used by the kythe project using
(experimental) action listeners.
https://github.com/google/kythe/blob/master/tools/cpp/generate_compilation_database.sh
"""

CompilationAspect = provider()

_cpp_extensions = ["cc", "cpp", "cxx"]

def _compilation_db_json(compilation_db):
    # Return a JSON string for the compilation db entries.

    entries = [entry.to_json() for entry in compilation_db]
    return ",\n ".join(entries)

def _is_cpp_target(srcs):
    for src in srcs:
        for extension in _cpp_extensions:
            if src.extension == extension:
                return True
    return False

def _compilation_database_aspect_impl(target, ctx):
    # Write the compile commands for this target to a file, and return
    # the commands for the transitive closure.

    compilation_db = []

    cpp_fragment = ctx.fragments.cpp
    compiler = str(cpp_fragment.compiler_executable)
    compile_flags = (cpp_fragment.compiler_options(ctx.features)
                     + cpp_fragment.c_options
                     + target.cc.compile_flags
                     + ctx.rule.attr.copts
                     + cpp_fragment.unfiltered_compiler_options(ctx.features))

    # system built-in directories (helpful for macOS).
    if cpp_fragment.libc == "macosx":
        compile_flags += ["-isystem " + str(d)
                          for d in cpp_fragment.built_in_include_directories]

    srcs = [f for src in ctx.rule.attr.srcs for f in src.files]
    if "hdrs" in dir(ctx.rule.attr):
        srcs += [f for src in ctx.rule.attr.hdrs for f in src.files]

    # This is useful for compiling .h headers as C++ code.
    force_cpp_mode_option = ""
    if _is_cpp_target(srcs):
        compile_flags += cpp_fragment.cxx_options(ctx.features)
        force_cpp_mode_option = " -x c++"

    compile_command = compiler + " " + " ".join(compile_flags) + force_cpp_mode_option  

    for src in srcs:
        command_for_file = compile_command + " -c " + src.path

        bazel_workspace_dir = "__WORKSPACE_ROOT__" + "/bazel-" + ctx.workspace_name
        compilation_db.append(
            struct(directory=bazel_workspace_dir, command=command_for_file, file=src.path))

    # Write the commands for this target.
    compdb_file = ctx.actions.declare_file(ctx.label.name + ".compile_commands.json")
    ctx.actions.write(
        content = _compilation_db_json(compilation_db),
        output = compdb_file)

    # Collect all transitive dependencies.
    compilation_db = depset(compilation_db)
    all_compdb_files = depset([compdb_file])
    for dep in ctx.rule.attr.deps:
        compilation_db += dep[CompilationAspect].compilation_db
        all_compdb_files += dep[OutputGroupInfo].compdb_files

    return [CompilationAspect(compilation_db=compilation_db),
            OutputGroupInfo(compdb_files=all_compdb_files)]


compilation_database_aspect = aspect(
    attr_aspects = ["deps"],
    fragments = ["cpp"],
    required_aspect_providers = [CompilationAspect],
    implementation = _compilation_database_aspect_impl,
)


def _compilation_database_impl(ctx):
    # Generates a single compile_commands.json file with the
    # transitive depset of specified targets.

    compilation_db = depset()
    for target in ctx.attr.targets:
        compilation_db += target[CompilationAspect].compilation_db

    content = "[\n" + _compilation_db_json(compilation_db) + "\n]\n"
    if ctx.attr.remove_workspace_root_marker:
        content = content.replace("__WORKSPACE_ROOT__/", "")
    ctx.file_action(output=ctx.outputs.filename, content=content)


compilation_database = rule(
    attrs = {
        "targets": attr.label_list(
            aspects = [compilation_database_aspect],
            doc = "List of all cc targets which should be included."),
        "remove_workspace_root_marker": attr.bool(
            default = True,
            doc = ("To add an absolute path to workspace root a placeholder '__WORKSPACE_ROOT__' is added which is removed by default 'True', providing a relative path to 'bazel-{workspace name}'." +
                   "Set to 'False', keeps the placeholder which allows to replace with project root directory in a post-processing step.")),
    },
    outputs = {
        "filename": "compile_commands.json",
    },
    implementation = _compilation_database_impl,
)
