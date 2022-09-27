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
load("@com_grail_bazel_config_compdb//:config.bzl", "ACTION_NAMES", "ALLOW_CUDA_HDRS", "ALLOW_CUDA_SRCS", "BuildSettingInfo", "CudaArchsInfo", "CudaInfo", "config_helper", "cuda_enable", "cuda_helper", "cuda_path", "find_cuda_toolchain", "paths", "unique", "use_cuda_toolchain")

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

_cuda_rules = [
    "cuda_library",
]

_all_rules = _cc_rules + _objc_rules + _cuda_rules

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
        options.append("-isystem {}".format(system_include))

    for include in compilation_context.includes.to_list():
        if len(include) == 0:
            include = "."
        options.append("-I {}".format(include))

    for quote_include in compilation_context.quote_includes.to_list():
        if len(quote_include) == 0:
            quote_include = "."
        options.append("-iquote {}".format(quote_include))

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
        compile_flags.append("-x c++")  # Force language mode for header files.
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

    # Add automatically `-std=` compilation command for clang.
    # Only take effect on the first matched value.
    value = None
    for option in compiler_options:
        if option.find("/std:") != -1:
            start = option.index("/std:")
            value = "-std=" + option[start + 5:start + 10]

    cmdline_list = [compiler]
    cmdline_list.extend(compiler_options)
    if value != None:
        cmdline_list.append(value)
    cmdline_list.extend(compile_flags)
    cmdline = " ".join(cmdline_list)

    compile_commands = []
    for src in srcs:
        compile_commands.append(struct(
            cmdline = cmdline + " -c " + src.path,
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
        compile_flags.append("-x objective-c++")  # Force language mode for header files.
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
        compile_flags.append("-x objective-c")  # Force language mode for header files.

    frameworks = (
        ["-F {}/..".format(val) for val in target.objc.static_framework_paths.to_list()] +
        ["-F {}/..".format(val) for val in target.objc.dynamic_framework_paths.to_list()]
    )
    compile_flags.extend(frameworks)

    compile_flags.extend(ctx.rule.attr.copts if "copts" in dir(ctx.rule.attr) else [])

    xcode_paths = _xcode_paths(ctx)
    system_flags = [
        "-isysroot {}".format(xcode_paths.sdk_root),
        "-F {}/System/Library/Frameworks".format(xcode_paths.sdk_root),
        "-F {}/Developer/Library/Frameworks".format(xcode_paths.platform_root),
    ]

    cmdline_list = [compiler]
    cmdline_list.extend(compiler_options)
    cmdline_list.extend(system_flags)
    cmdline_list.extend(compile_flags)
    cmdline = " ".join(cmdline_list)

    compile_commands = []
    for src in srcs:
        arc_flag = "" if src in non_arc_srcs else " -fobjc-arc"
        compile_commands.append(struct(
            cmdline = cmdline + arc_flag + " -c " + src.path,
            src = src,
        ))
    return compile_commands

def _check_src_extension(file, allowed_src_files):
    for pattern in allowed_src_files:
        if file.basename.endswith(pattern):
            return True
    return False

def _check_srcs_extensions(ctx, allowed_src_files, rule_name):
    for src in ctx.rule.attr.srcs:
        files = src[DefaultInfo].files.to_list()
        if len(files) == 1 and files[0].is_source:
            if not _check_src_extension(files[0], allowed_src_files) and not files[0].is_directory:
                fail("in srcs attribute of {} rule {}: source file '{}' is misplaced here".format(rule_name, ctx.label, str(src.label)))
        else:
            at_least_one_good = False
            for file in files:
                if _check_src_extension(file, allowed_src_files) or file.is_directory:
                    at_least_one_good = True
                    break
            if not at_least_one_good:
                fail("'{}' does not produce any {} srcs files".format(str(src.label), rule_name), attr = "srcs")

def _resolve_workspace_root_includes(ctx):
    src_path = paths.normalize(ctx.label.workspace_root)
    bin_path = paths.normalize(paths.join(ctx.bin_dir.path, src_path))
    return src_path, bin_path

def _resolve_includes(ctx, path):
    if paths.is_absolute(path):
        fail("invalid absolute path", path)

    src_path = paths.normalize(paths.join(ctx.label.workspace_root, ctx.label.package, path))
    bin_path = paths.join(ctx.bin_dir.path, src_path)
    return src_path, bin_path

def _check_opts(opt):
    opt = opt.strip()
    if (opt.startswith("--generate-code") or opt.startswith("-gencode") or
        opt.startswith("--gpu-architecture") or opt.startswith("-arch") or
        opt.startswith("--gpu-code") or opt.startswith("-code") or
        opt.startswith("--relocatable-device-code") or opt.startswith("-rdc") or
        opt.startswith("--cuda") or opt.startswith("-cuda") or
        opt.startswith("--preprocess") or opt.startswith("-E") or
        opt.startswith("--compile") or opt.startswith("-c") or
        opt.startswith("--cubin") or opt.startswith("-cubin") or
        opt.startswith("--ptx") or opt.startswith("-ptx") or
        opt.startswith("--fatbin") or opt.startswith("-fatbin") or
        opt.startswith("--device-link") or opt.startswith("-dlink") or
        opt.startswith("--lib") or opt.startswith("-lib") or
        opt.startswith("--generate-dependencies") or opt.startswith("-M") or
        opt.startswith("--generate-nonsystem-dependencies") or opt.startswith("-MM") or
        opt.startswith("--run") or opt.startswith("-run")):
        fail(opt, "is not allowed to be specified directly via copts")
    return True

def _get_cuda_archs_info(ctx):
    return ctx.rule.attr._default_cuda_archs[CudaArchsInfo]

def _create_common_info(
        cuda_archs_info = None,
        includes = [],
        quote_includes = [],
        system_includes = [],
        headers = [],
        transitive_headers = [],
        defines = [],
        local_defines = [],
        compile_flags = [],
        link_flags = [],
        host_defines = [],
        host_local_defines = [],
        host_compile_flags = [],
        host_link_flags = [],
        ptxas_flags = [],
        transitive_linking_contexts = []):
    return struct(
        cuda_archs_info = cuda_archs_info,
        includes = includes,
        quote_includes = quote_includes,
        system_includes = system_includes,
        headers = depset(headers, transitive = transitive_headers),
        defines = defines,
        local_defines = local_defines,
        compile_flags = compile_flags,
        link_flags = link_flags,
        host_defines = host_defines,
        host_local_defines = host_local_defines,
        host_compile_flags = host_compile_flags,
        host_link_flags = host_link_flags,
        ptxas_flags = ptxas_flags,
        transitive_linker_inputs = [ctx.linker_inputs for ctx in transitive_linking_contexts],
        transitive_linking_contexts = transitive_linking_contexts,
    )

def _create_common(ctx):
    """Helper to gather and process various information from `ctx` object to ease the parameter passing for internal macros.

    See `cuda_helper.create_common_info` what information a common object encapsulates.
    """
    attr = ctx.rule.attr

    # gather include info
    includes = []
    system_includes = []
    quote_includes = []
    quote_includes.extend(_resolve_workspace_root_includes(ctx))
    for inc in attr.includes:
        system_includes.extend(_resolve_includes(ctx, inc))
    for dep in attr.deps:
        if CcInfo in dep:
            includes.extend(dep[CcInfo].compilation_context.includes.to_list())
            system_includes.extend(dep[CcInfo].compilation_context.system_includes.to_list())
            quote_includes.extend(dep[CcInfo].compilation_context.quote_includes.to_list())

    # gather header info
    public_headers = []
    private_headers = []
    for fs in attr.hdrs:
        public_headers.extend(fs.files.to_list())
    for fs in attr.srcs:
        hdr = [f for f in fs.files.to_list() if _check_src_extension(f, ALLOW_CUDA_HDRS)]
        private_headers.extend(hdr)
    headers = public_headers + private_headers
    transitive_headers = []
    for dep in attr.deps:
        if CcInfo in dep:
            transitive_headers.append(dep[CcInfo].compilation_context.headers)

    # gather linker info
    builtin_linking_contexts = []
    if hasattr(attr, "_builtin_deps"):
        builtin_linking_contexts = [dep[CcInfo].linking_context for dep in attr._builtin_deps if CcInfo in dep]

    transitive_linking_contexts = [dep[CcInfo].linking_context for dep in attr.deps if CcInfo in dep]
    transitive_linking_contexts.extend(builtin_linking_contexts)

    # gather compile info
    defines = []
    local_defines = [i for i in attr.local_defines]
    compile_flags = attr._default_host_copts[BuildSettingInfo].value + [o for o in attr.copts if _check_opts(o)]
    link_flags = []
    if hasattr(attr, "linkopts"):
        link_flags.extend([o for o in attr.linkopts if _check_opts(o)])
    host_defines = []
    host_local_defines = [i for i in attr.host_local_defines]
    host_compile_flags = [i for i in attr.host_copts]
    host_link_flags = []
    if hasattr(attr, "host_linkopts"):
        host_link_flags.extend([i for i in attr.host_linkopts])
    for dep in attr.deps:
        if CudaInfo in dep:
            defines.extend(dep[CudaInfo].defines.to_list())
        if CcInfo in dep:
            host_defines.extend(dep[CcInfo].compilation_context.defines.to_list())
    defines.extend(attr.defines)
    host_defines.extend(attr.host_defines)

    ptxas_flags = [o for o in attr.ptxasopts if _check_opts(o)]

    return _create_common_info(
        cuda_archs_info = _get_cuda_archs_info(ctx),
        includes = includes,
        quote_includes = quote_includes,
        system_includes = system_includes,
        headers = headers,
        transitive_headers = transitive_headers,
        defines = defines,
        local_defines = local_defines,
        compile_flags = compile_flags,
        link_flags = link_flags,
        host_defines = host_defines,
        host_local_defines = host_local_defines,
        host_compile_flags = host_compile_flags,
        host_link_flags = host_link_flags,
        ptxas_flags = ptxas_flags,
        transitive_linking_contexts = transitive_linking_contexts,
    )

def _get_all_unsupported_features(ctx, cuda_toolchain, unsupported_features):
    all_unsupported = list(ctx.disabled_features)
    all_unsupported.extend([f[1:] for f in ctx.rule.attr.features if f.startswith("-")])
    if unsupported_features != None:
        all_unsupported.extend(unsupported_features)
    return unique(all_unsupported)

def _get_all_requested_features(ctx, cuda_toolchain, requested_features):
    all_features = []
    compilation_mode = ctx.var.get("COMPILATION_MODE", None)
    if compilation_mode == None:
        compilation_mode = "opt"
    all_features.append(compilation_mode)

    all_features.extend(ctx.features)
    all_features.extend([f for f in ctx.rule.attr.features if not f.startswith("-")])
    all_features.extend(requested_features)
    all_features = unique(all_features)

    # https://github.com/bazelbuild/bazel/blob/41feb616ae/src/main/java/com/google/devtools/build/lib/rules/cpp/CcCommon.java#L953-L967
    if "static_link_msvcrt" in all_features:
        all_features.append("static_link_msvcrt_debug" if compilation_mode == "dbg" else "static_link_msvcrt_no_debug")
    else:
        all_features.append("dynamic_link_msvcrt_debug" if compilation_mode == "dbg" else "dynamic_link_msvcrt_no_debug")

    return all_features

def _configure_features(ctx, cuda_toolchain, requested_features = None, unsupported_features = None, _debug = False):
    all_requested_features = _get_all_requested_features(ctx, cuda_toolchain, requested_features)
    all_unsupported_features = _get_all_unsupported_features(ctx, cuda_toolchain, unsupported_features)
    return config_helper.configure_features(
        selectables_info = cuda_toolchain.selectables_info,
        requested_features = all_requested_features,
        unsupported_features = all_unsupported_features,
        _debug = _debug,
    )

def _cuda_compile_commands(ctx, target, cc_toolchain):
    for cuda_rule in _cuda_rules:
        _check_srcs_extensions(ctx, ALLOW_CUDA_SRCS + ALLOW_CUDA_HDRS, cuda_rule)

    cuda_toolchain = find_cuda_toolchain(ctx)
    cuda_common = _create_common(ctx)
    feature_configuration = _configure_features(
        ctx = ctx,
        cuda_toolchain = cuda_toolchain,
        requested_features = ctx.features + [ACTION_NAMES.cuda_compile],
        unsupported_features = ctx.disabled_features + DISABLED_FEATURES,
    )

    compile_flags = []
    for define in cuda_common.defines:
        compile_flags.append("-D\"{}\"".format(define))

    for define in cuda_common.local_defines:
        compile_flags.append("-D\"{}\"".format(define))

    for system_include in cuda_common.system_includes:
        if len(system_include) == 0:
            system_include = "."
        compile_flags.append("-isystem {}".format(system_include))

    for include in cuda_common.includes:
        if len(include) == 0:
            include = "."
        compile_flags.append("-I {}".format(include))

    for quote_include in cuda_common.quote_includes:
        if len(quote_include) == 0:
            quote_include = "."
        compile_flags.append("-iquote {}".format(quote_include))

    host_compiler = cc_toolchain.compiler_executable
    cuda_compiler = cuda_toolchain.compiler_executable

    srcs = _sources(ctx, target)

    compiler_options = None
    compile_variables = cuda_helper.create_compile_variables(
        feature_configuration = feature_configuration,
        cuda_toolchain = cuda_toolchain,
        compile_flags = cuda_common.compile_flags,
        cuda_archs_info = cuda_common.cuda_archs_info,
        host_compiler = host_compiler,
        # No need for source_file and output_file.
        source_file = "",
        output_file = "",
    )

    compiler_options = cuda_helper.get_command_line(
        info = feature_configuration,
        action = ACTION_NAMES.cuda_compile,
        value = compile_variables,
    )

    # No need for source_file and output_file.
    compiler_options.remove("-o")
    compiler_options.remove("")
    compiler_options.remove("-c")
    compiler_options.remove("")

    cmdline_list = [cuda_compiler]
    cmdline_list.extend(compiler_options)
    cmdline_list.extend(compile_flags)
    cmdline_list.append("--cuda-path=%s" % cuda_path)
    cmdline = " ".join(cmdline_list)

    compile_commands = []
    for src in srcs:
        compile_commands.append(struct(
            # Add source_file.
            cmdline = cmdline + " -c " + src.path,
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

    transitive_compilation_db = []
    all_compdb_files = []
    all_header_files = []
    for dep in deps:
        if CompilationAspect not in dep:
            continue
        transitive_compilation_db.append(dep[CompilationAspect].compilation_db)
        all_compdb_files.append(dep[OutputGroupInfo].compdb_files)
        all_header_files.append(dep[OutputGroupInfo].header_files)

    # TODO: Remove CcInfo check once https://github.com/bazelbuild/bazel/pull/15426 is released
    # We support only these rule kinds.
    if ctx.rule.kind not in _all_rules or CcInfo not in target:
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
    elif cuda_enable and ctx.rule.kind in _cuda_rules:
        compile_commands = _cuda_compile_commands(ctx = ctx, target = target, cc_toolchain = cc_toolchain)
    else:
        fail("unsupported rule: " + ctx.rule.kind)

    srcs = []
    for compile_command in compile_commands:
        exec_root_marker = "__EXEC_ROOT__"
        compilation_db.append(
            struct(command = compile_command.cmdline, directory = exec_root_marker, file = compile_command.src.path),
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
    if cuda_enable and ctx.rule.kind in _cuda_rules:
        cuda_common = _create_common(ctx)
        all_header_files.append(cuda_common.headers)

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
    attr_aspects = ["srcs", "deps"],
    attrs = {
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
        "_xcode_config": attr.label(default = Label("@bazel_tools//tools/osx:current_xcode_config")),
    },
    fragments = ["cpp", "objc", "apple"],
    provides = [CompilationAspect],
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"] + [use_cuda_toolchain] if cuda_enable else [],
    implementation = _compilation_database_aspect_impl,
    apply_to_generating_rules = True,
)
