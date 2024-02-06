#!/usr/bin/python3

# Copyright 2024 The Bazel Authors.
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

"""Generates a compile_commands.json file at $(bazel info workspace) for
libclang based tools.

This is inspired from
https://github.com/google/kythe/blob/master/tools/cpp/generate_compilation_database.sh
"""

import argparse
import json
import os
import pathlib
import subprocess
import sys
import tempfile


_BAZEL = os.getenv("BAZEL_COMPDB_BAZEL_PATH") or "bazel"

_OUTPUT_GROUPS = "compdb_files,header_files"


def bazel_info():
    """Returns a dict containing key values from bazel info."""

    bazel_info_dict = dict()
    try:
        out = subprocess.check_output([_BAZEL, 'info']).decode('utf-8').strip().split('\n')
    except subprocess.CalledProcessError as err:
        # This exit code is returned when this command is run outside of a bazel workspace.
        if err.returncode == 2:
            sys.exit(0)
        sys.exit(err.returncode)

    for line in out:
        key_val = line.strip().partition(": ")
        bazel_info_dict[key_val[0]] = key_val[2]

    return bazel_info_dict

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-s", "--source_dir", default=False, action="store_true",
                        help="use the original source directory instead of bazel execroot")
    parser.add_argument("-q", "--query_expr", default="//...",
                        help="bazel query expr to find targets")
    parser.add_argument('bazel_args', nargs=argparse.REMAINDER,
                        help="")
    args = parser.parse_args()

    user_build_args = []
    if len(args.bazel_args) > 0:
        if args.bazel_args[0] != '--':
            msg = "additional bazel args '%s' must start with --" % " ".join(args.bazel_args)
            raise Exception(msg)
        user_build_args = args.bazel_args[1:] # Ignore the first '--'

    bazel_info_dict = bazel_info()
    bazel_exec_root = bazel_info_dict['execution_root']
    bazel_workspace = bazel_info_dict['workspace']
    compdb_file = os.path.join(bazel_workspace, "compile_commands.json")

    os.chdir(bazel_workspace)

    aspects_dir = os.path.dirname(os.path.realpath(__file__))

    query = ('kind("^cc_(library|binary|test|inc_library|proto_library)", {query_expr}) ' +
             'union kind("^objc_(library|binary|test)", {query_expr})').format(
                 query_expr=args.query_expr)
    query_cmd = [_BAZEL, 'query']
    query_cmd.extend(['--noshow_progress', '--noshow_loading_progress', '--output=label'])
    query_cmd.append(query)

    targets_file = tempfile.NamedTemporaryFile()
    subprocess.check_call(query_cmd, stdout=targets_file)

    # Clean any previously generated files.
    for db in pathlib.Path(bazel_exec_root).glob('**/*.compile_commands.json'):
        db.unlink()

    build_args = [
        '--override_repository=bazel_compdb={}'.format(aspects_dir),
        '--aspects=@bazel_compdb//:aspects.bzl%compilation_database_aspect',
        '--noshow_progress',
        '--noshow_loading_progress',
        '--output_groups={}'.format(_OUTPUT_GROUPS),
        '--target_pattern_file={}'.format(targets_file.name),
    ]
    build_cmd = [_BAZEL, 'build']
    build_cmd.extend(build_args)
    build_cmd.extend(user_build_args)
    subprocess.check_call(build_cmd, stdout=subprocess.DEVNULL)

    targets_file.close()

    db_entries = []
    for db in pathlib.Path(bazel_exec_root).glob('**/*.compile_commands.json'):
        with open(db, 'r') as f:
            db_entries.extend(json.load(f))

    def replace_execroot_marker(db_entry):
        if 'directory' in db_entry and db_entry['directory'] == '__EXEC_ROOT__':
            db_entry['directory'] = bazel_workspace if args.source_dir else bazel_exec_root
        if 'command' in db_entry:
            db_entry['command'] = (
                db_entry['command'].replace('-isysroot __BAZEL_XCODE_SDKROOT__', ''))
        return db_entry
    db_entries = list(map(replace_execroot_marker, db_entries))

    with open(compdb_file, 'w') as outdb:
        json.dump(db_entries, outdb, indent=2)

    if args.source_dir:
        link_name = os.path.join(bazel_workspace, 'external')
        try:
            os.remove(link_name)
        except FileNotFoundError:
            pass
        # This is for libclang to help find source files from external repositories.
        os.symlink(os.path.join(bazel_exec_root, 'external'),
                   link_name,
                   target_is_directory=True)
    else:
        # This is for YCM to help find the DB when following generated files.
        # The file may be deleted by bazel on the next build.
        link_name = os.path.join(bazel_exec_root, "compile_commands.json")
        try:
            os.remove(link_name)
        except FileNotFoundError:
            pass
        os.symlink(compdb_file, link_name)
