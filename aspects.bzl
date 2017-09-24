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


def _compilation_database_aspect_impl(target, ctx):
    # Write the compile commands for this target to a file, and return
    # the commands for the transitive closure.

    compilation_db = []
    sources = [f for src in ctx.rule.attr.srcs for f in src.files]
    for src in sources:
        if not src.is_source:
            continue 

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

        # This is useful for compiling .h headers by libclang.
        # For headers, YCM finds a counterpart source file for getting flags.
        # TODO: Explicitly add headers for which a counterpart source file does not exist.
        force_cpp_mode_option = ""
        for extension in _cpp_extensions:
            if src.extension == extension:
                compile_flags += cpp_fragment.cxx_options(ctx.features)
                force_cpp_mode_option = " -x c++"
                break

        commandline = (compiler + " " + " ".join(compile_flags) + force_cpp_mode_option +
                       " -c " + src.short_path)

        exec_root_marker = "__EXEC_ROOT__"
        compilation_db.append(
            struct(directory=exec_root_marker, command=commandline, file=src.path))

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

    content = "[\n" + _compilation_db_json(compilation_db) + "\n]"
    ctx.file_action(output=ctx.outputs.filename, content=content)


compilation_database = rule(
    attrs = {
        "targets": attr.label_list(aspects = [compilation_database_aspect]),
    },
    outputs = {
        "filename": "compile_commands.json",
    },
    implementation = _compilation_database_impl,
)
