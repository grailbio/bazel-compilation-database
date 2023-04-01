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
    "C_COMPILE_ACTION_NAME",
    "OBJCPP_COMPILE_ACTION_NAME",
    "OBJC_COMPILE_ACTION_NAME",
)

CompilationAspect = provider()

_cpp_header_extensions = [
    "hh",
    "hxx",
    "ipp",
    "hpp",
]

_c_or_cpp_header_extensions = ["h"] + _cpp_header_extensions

_cpp_extensions = [
    "cc",
    "cpp",
    "cxx",
] + _cpp_header_extensions

_cc_rules = [
    "cc_library",
    "cc_binary",
    "cc_test",
    "cc_inc_library",
    "cc_proto_library",
]

_objc_rules = [
    "objc_library",
    "objc_binary",
]

_all_rules = _cc_rules + _objc_rules

# Temporary fix for https://github.com/grailbio/bazel-compilation-database/issues/101.
DISABLED_FEATURES = [
    "module_maps",
]

def _is_cpp_target(srcs):
    if all([src.extension in _c_or_cpp_header_extensions for src in srcs]):
        return True  # assume header-only lib is c++
    return any([src.extension in _cpp_extensions for src in srcs])

def _is_objcpp_target(srcs):
    return any([src.extension == "mm" for src in srcs])

def _sources(ctx, target):
    srcs = []
    if hasattr(ctx.rule.attr, "srcs"):
        srcs += [f for src in ctx.rule.attr.srcs for f in src.files.to_list()]
    if hasattr(ctx.rule.attr, "hdrs"):
        srcs += [f for src in ctx.rule.attr.hdrs for f in src.files.to_list()]

    return srcs

# Function copied from https://gist.github.com/oquenchil/7e2c2bd761aa1341b458cc25608da50c
# TODO: Directly use create_compile_variables and get_memory_inefficient_command_line.
def _get_compile_flags(dep):
    options = []
    compilation_context = dep[CcInfo].compilation_context
    for define in compilation_context.defines.to_list():
        options.append("-D\"{}\"".format(define))

    for define in compilation_context.local_defines.to_list():
        options.append("-D\"{}\"".format(define))

    for system_include in compilation_context.system_includes.to_list():
        if len(system_include) == 0:
            system_include = "."
        options.extend(("-isystem", system_include))

    for include in compilation_context.includes.to_list():
        if len(include) == 0:
            include = "."
        options.extend(("-I", include))

    for quote_include in compilation_context.quote_includes.to_list():
        if len(quote_include) == 0:
            quote_include = "."
        options.extend(("-iquote", quote_include))

    for framework_include in compilation_context.framework_includes.to_list():
        options.append("-F\"{}\"".format(framework_include))

    return options

def _xcode_paths(ctx):
    xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig]

    sdk_version = xcode_config.sdk_version_for_platform(ctx.fragments.apple.single_arch_platform)
    apple_env = apple_common.target_apple_env(xcode_config, ctx.fragments.apple.single_arch_platform)
    sdk_platform = apple_env["APPLE_SDK_PLATFORM"]

    # FIXME is there any way of getting the SDKROOT value here? The only thing that seems to know about it is
    # XcodeLocalEnvProvider, but I can't seem to find a way to access that
    platform_root = "/Applications/Xcode.app/Contents/Developer/Platforms/{platform}.platform".format(platform = sdk_platform)
    sdk_root = "/Applications/Xcode.app/Contents/Developer/Platforms/{platform}.platform/Developer/SDKs/{platform}{version}.sdk".format(platform = sdk_platform, version = sdk_version)

    return struct(
        platform_root = platform_root,
        sdk_root = sdk_root,
    )

def _cc_compile_commands(ctx, target, feature_configuration, cc_toolchain):
    compiler = str(
        cc_common.get_tool_for_action(
            feature_configuration = feature_configuration,
            action_name = C_COMPILE_ACTION_NAME,
        ),
    )
    compile_flags = _get_compile_flags(target)

    srcs = _sources(ctx, target)
    if ctx.rule.kind == "cc_proto_library":
        srcs += [f for f in target.files.to_list() if f.extension in ["h", "cc"]]

    # We currently recognize an entire target as C++ or C. This can probably be
    # made better for targets that have a mix of C and C++ files.
    is_cpp_target = _is_cpp_target(srcs)

    compiler_options = None
    if is_cpp_target:
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
        compile_flags.extend(("-x", "c++"))  # Force language mode for header files.
    else:
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

    compile_flags.extend(ctx.rule.attr.copts if "copts" in dir(ctx.rule.attr) else [])

    cmdline_list = [compiler]
    cmdline_list.extend(compiler_options)
    cmdline_list.extend(compile_flags)

    compile_commands = []
    for src in srcs:
        compile_commands.append(struct(
            cmdline_list = tuple(cmdline_list + ["-c", src.path]),
            src = src,
        ))
    return compile_commands

def _objc_compile_commands(ctx, target, feature_configuration, cc_toolchain):
    compiler = str(
        cc_common.get_tool_for_action(
            feature_configuration = feature_configuration,
            action_name = OBJC_COMPILE_ACTION_NAME,
        ),
    )
    compile_flags = _get_compile_flags(target)

    srcs = _sources(ctx, target)

    non_arc_srcs = []
    if "non_arc_srcs" in dir(ctx.rule.attr):
        non_arc_srcs += [f for src in ctx.rule.attr.non_arc_srcs for f in src.files.to_list()]
    srcs.extend(non_arc_srcs)

    # We currently recognize an entire target as objective-c++ or not. This can
    # probably be made better for targets that have a mix of files.
    is_objcpp_target = _is_objcpp_target(srcs)

    compiler_options = None
    if is_objcpp_target:
        compile_variables = cc_common.create_compile_variables(
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            user_compile_flags = ctx.fragments.objc.copts,
            add_legacy_cxx_options = True,
        )
        compiler_options = cc_common.get_memory_inefficient_command_line(
            feature_configuration = feature_configuration,
            action_name = OBJCPP_COMPILE_ACTION_NAME,
            variables = compile_variables,
        )
        compile_flags.extend(("-x", "objective-c++"))  # Force language mode for header files.
    else:
        compile_variables = cc_common.create_compile_variables(
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            user_compile_flags = ctx.fragments.objc.copts,
        )
        compiler_options = cc_common.get_memory_inefficient_command_line(
            feature_configuration = feature_configuration,
            action_name = OBJC_COMPILE_ACTION_NAME,
            variables = compile_variables,
        )
        compile_flags.extend(("-x","objective-c"))  # Force language mode for header files.

    frameworks = (
        ["-F {}/..".format(val) for val in target.objc.static_framework_paths.to_list()] +
        ["-F {}/..".format(val) for val in target.objc.dynamic_framework_paths.to_list()]
    )
    compile_flags.extend(frameworks)

    compile_flags.extend(ctx.rule.attr.copts if "copts" in dir(ctx.rule.attr) else [])

    xcode_paths = _xcode_paths(ctx)
    system_flags = [
        "-isysroot", xcode_paths.sdk_root,
        "-F", "{}/System/Library/Frameworks".format(xcode_paths.sdk_root),
        "-F", "{}/Developer/Library/Frameworks".format(xcode_paths.platform_root),
    ]

    cmdline_list = [compiler]
    cmdline_list.extend(compiler_options)
    cmdline_list.extend(system_flags)
    cmdline_list.extend(compile_flags)

    compile_commands = []
    for src in srcs:
        arc_flag = None if src in non_arc_srcs else "-fobjc-arc"
        compile_commands.append(struct(
            cmdline_list = tuple(cmdline_list + [arc_flag, "-c", src.path]),
            src = src,
        ))
    return compile_commands

def _compilation_database_aspect_impl(target, ctx):
    # Write the compile commands for this target to a file, and return
    # the commands for the transitive closure.

    # Collect any aspects from all transitive dependencies.
    # Note that this should also apply to filegroup type targets which may have
    # cc_binary targets in their srcs attribute.
    deps = []
    if hasattr(ctx.rule.attr, "srcs"):
        deps.extend(ctx.rule.attr.srcs)
    if hasattr(ctx.rule.attr, "deps"):
        deps.extend(ctx.rule.attr.deps)
    if hasattr(ctx.rule.attr, "implementation_deps"):
        deps.extend(ctx.rule.attr.implementation_deps)

    transitive_compilation_db = []
    all_compdb_files = []
    all_header_files = []
    for dep in deps:
        if CompilationAspect not in dep:
            continue
        transitive_compilation_db.append(dep[CompilationAspect].compilation_db)
        all_compdb_files.append(dep[OutputGroupInfo].compdb_files)
        all_header_files.append(dep[OutputGroupInfo].header_files)

    if ctx.rule.kind not in _all_rules:
        return [
            CompilationAspect(compilation_db = depset(transitive = transitive_compilation_db)),
            OutputGroupInfo(
                compdb_files = depset(transitive = all_compdb_files),
                header_files = depset(transitive = all_header_files),
                direct_src_files = [],
            ),
        ]

    compilation_db = []

    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features + DISABLED_FEATURES,
    )

    if ctx.rule.kind in _cc_rules:
        compile_commands = _cc_compile_commands(ctx, target, feature_configuration, cc_toolchain)
    elif ctx.rule.kind in _objc_rules:
        compile_commands = _objc_compile_commands(ctx, target, feature_configuration, cc_toolchain)
    else:
        fail("unsupported rule: " + ctx.rule.kind)

    srcs = []
    for compile_command in compile_commands:
        exec_root_marker = "__EXEC_ROOT__"
        compilation_db.append(
            struct(arguments = compile_command.cmdline_list, directory = exec_root_marker, file = compile_command.src.path),
        )
        srcs.append(compile_command.src)

    # Write the commands for this target.
    compdb_file = ctx.actions.declare_file(ctx.label.name + ".compile_commands.json")
    ctx.actions.write(
        content = json.encode(compilation_db),
        output = compdb_file,
    )

    compilation_db = depset(compilation_db, transitive = transitive_compilation_db)
    all_compdb_files = depset([compdb_file], transitive = all_compdb_files)
    all_header_files.append(target[CcInfo].compilation_context.headers)

    return [
        CompilationAspect(compilation_db = compilation_db),
        OutputGroupInfo(
            compdb_files = all_compdb_files,
            header_files = depset(transitive = all_header_files),
            # Provide direct src files of this target for people who want to
            # run clang-tidy or similar tools with the compilation database
            # on the source files of this target.
            # See https://github.com/grailbio/bazel-compilation-database/pull/53.
            direct_src_files = srcs,
        ),
    ]

compilation_database_aspect = aspect(
    # Also include srcs in the attribute aspects so people can use filegroup targets.
    # See https://github.com/grailbio/bazel-compilation-database/issues/84.
    attr_aspects = ["srcs", "deps", "implementation_deps"],
    attrs = {
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
        "_xcode_config": attr.label(default = Label("@bazel_tools//tools/osx:current_xcode_config")),
    },
    fragments = ["cpp", "objc", "apple"],
    provides = [CompilationAspect],
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    implementation = _compilation_database_aspect_impl,
    apply_to_generating_rules = True,
)
