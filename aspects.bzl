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

load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load(
    "@bazel_tools//tools/build_defs/cc:action_names.bzl",
    "CPP_COMPILE_ACTION_NAME",
    "CPP_LINK_DYNAMIC_LIBRARY_ACTION_NAME",
    "C_COMPILE_ACTION_NAME",
)

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

def _sources(target, ctx):
    srcs = []
    if "srcs" in dir(ctx.rule.attr):
        srcs += [f for src in ctx.rule.attr.srcs for f in src.files]
    if "hdrs" in dir(ctx.rule.attr):
        srcs += [f for src in ctx.rule.attr.hdrs for f in src.files]

    if ctx.rule.kind == "cc_proto_library":
        srcs += [f for f in target.files if f.extension in ["h", "cc"]]

    return srcs

def _compilation_database_aspect_impl(target, ctx):
    # Write the compile commands for this target to a file, and return
    # the commands for the transitive closure.

    # We support only these rule kinds.
    if ctx.rule.kind not in ["cc_library", "cc_binary", "cc_test",
                             "cc_inc_library", "cc_proto_library"]:
        return []

    compilation_db = []

    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    compile_variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = ctx.fragments.cpp.copts,
    )
    compiler_options = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = C_COMPILE_ACTION_NAME,
        variables = compile_variables,
    )
    compiler = str(
        cc_common.get_tool_for_action(
            feature_configuration = feature_configuration,
            action_name = C_COMPILE_ACTION_NAME,
        ),
    )

    srcs = _sources(target, ctx)
    if not srcs:
        # This should not happen for any of our supported rule kinds.
        print("Rule with no sources: " + str(target.label))
        return []

    # This is useful for compiling .h headers as C++ code.
    force_cpp_mode_option = ""
    if _is_cpp_target(srcs):
        compile_variables = cc_common.create_compile_variables(
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            user_compile_flags = ctx.fragments.cpp.cxxopts +
                                 ctx.fragments.cpp.copts,
            add_legacy_cxx_options = True,
        )
        compiler_options = cc_common.get_memory_inefficient_command_line(
            feature_configuration = feature_configuration,
            action_name = CPP_COMPILE_ACTION_NAME,
            variables = compile_variables,
        )
        force_cpp_mode_option = " -x c++"

    compile_flags = (compiler_options +
                     target.cc.compile_flags +
                     (ctx.rule.attr.copts if "copts" in dir(ctx.rule.attr) else []))
    # system built-in directories (helpful for macOS).
    if cc_toolchain.libc == "macosx":
        compile_flags += ["-isystem " + str(d)
                          for d in cc_toolchain.built_in_include_directories]
    compile_command = compiler + " " + " ".join(compile_flags) + force_cpp_mode_option

    for src in srcs:
        command_for_file = compile_command + " -c " + src.path

        exec_root_marker = "__EXEC_ROOT__"
        compilation_db.append(
            struct(directory=exec_root_marker, command=command_for_file, file=src.path))

    # Write the commands for this target.
    compdb_file = ctx.actions.declare_file(ctx.label.name + ".compile_commands.json")
    ctx.actions.write(
        content = _compilation_db_json(compilation_db),
        output = compdb_file)

    # Collect all transitive dependencies.
    compilation_db = depset(compilation_db)
    all_compdb_files = depset([compdb_file])
    for dep in ctx.rule.attr.deps:
        if CompilationAspect not in dep:
            continue
        compilation_db += dep[CompilationAspect].compilation_db
        all_compdb_files += dep[OutputGroupInfo].compdb_files

    return [CompilationAspect(compilation_db=compilation_db),
            OutputGroupInfo(compdb_files=all_compdb_files)]


compilation_database_aspect = aspect(
    attr_aspects = ["deps"],
    fragments = ["cpp"],
    required_aspect_providers = [CompilationAspect],
    implementation = _compilation_database_aspect_impl,
    attrs = {
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
    },
)


def _compilation_database_impl(ctx):
    # Generates a single compile_commands.json file with the
    # transitive depset of specified targets.

    compilation_db = depset()
    for target in ctx.attr.targets:
        compilation_db += target[CompilationAspect].compilation_db

    content = "[\n" + _compilation_db_json(compilation_db) + "\n]\n"
    content = content.replace("__EXEC_ROOT__", ctx.attr.exec_root)
    ctx.file_action(output=ctx.outputs.filename, content=content)


compilation_database = rule(
    attrs = {
        "targets": attr.label_list(
            aspects = [compilation_database_aspect],
            doc = "List of all cc targets which should be included."),
        "exec_root": attr.string(
            default = "__EXEC_ROOT__",
            doc = "Execution root of Bazel as returned by 'bazel info execution_root'."),
    },
    outputs = {
        "filename": "compile_commands.json",
    },
    implementation = _compilation_database_impl,
)
