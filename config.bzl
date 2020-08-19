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

_compdb_config_repo_name = "bazel_compdb_config"
_exec_root_config_name = "exec_root"
_filter_flags_config_name = "filter_flags"

config_exec_root = "@{repo}//:{target}".format(
    repo=_compdb_config_repo_name,
    target=_exec_root_config_name
)

config_filter_flags = "@{repo}//:{target}".format(
    repo=_compdb_config_repo_name,
    target=_filter_flags_config_name
)


_config_build_file_header = """
package(default_visibility = ["//visibility:public"])
load("@{this_repo}//:custom_config.bzl", "custom_config_string", "custom_config_string_list")
"""

_config_string = """
custom_config_string(
    name = "{config_name}",
    value = "{value}",
)
"""

_config_string_list = """
custom_config_string_list(
    name = "{config_name}",
    value = {value},
)
"""

# Use repository rule to generate the exeroot path because `repository_ctx` is the bazel context
# capable of retrieving absolute file system path.
def _compdb_config_repository_impl(ctx):
    # Retrive the execution root of this build, as would be returned by `bazel info execution_root`
    # from the root path of the workspace, the whole point of this rule.
    relpath = "../../execroot/{workspace}".format(workspace=ctx.attr.workspace_name)
    exec_root = ctx.execute(["realpath", "-L", relpath]).stdout.rstrip("\n")

    # Retrieve the name under which this repository is loaded.
    this_repo = ctx.path(Label("//:config.bzl")).dirname.basename

    build_file_content = _config_build_file_header.format(this_repo = this_repo)
    build_file_content += _config_string.format(
        config_name = _exec_root_config_name,
        value = exec_root,
    )

    build_file_content += _config_string_list.format(
        config_name = _filter_flags_config_name,
        value = ctx.attr.filter_flags,
    )

    ctx.file("WORKSPACE.bazel", "workspace(name = \"{name}\")\n".format(name = ctx.name))
    ctx.file("BUILD.bazel", build_file_content)

    return ctx.attr

compdb_config_repository = repository_rule(
    implementation = _compdb_config_repository_impl,
    local = True,
    attrs = dict(
        workspace_name = attr.string(
            default = "__main__",
        ),
        filter_flags = attr.string_list(
            default = [
                "-isysroot __BAZEL_XCODE_SDKROOT__",
            ]
        ),
    ),
    doc = """A virtual repository for retriving absolute path of `execroot`."""
)

def config_clang_compdb(**kwargs):
    compdb_config_repository(name = _compdb_config_repo_name, **kwargs)
