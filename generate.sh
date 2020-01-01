#!/bin/bash

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

# Generates a compile_commands.json file at $(bazel info workspace) for
# libclang based tools.

# This is inspired from
# https://github.com/google/kythe/blob/master/tools/cpp/generate_compilation_database.sh

set -e

# This function is copied from https://source.bazel.build/bazel/+/master:scripts/packages/bazel.sh.
# `readlink -f` that works on OSX too.
function get_realpath() {
	if [ "$(uname -s)" == "Darwin" ]; then
		local queue="$1"
		if [[ "${queue}" != /* ]] ; then
			# Make sure we start with an absolute path.
			queue="${PWD}/${queue}"
		fi
		local current=""
		while [ -n "${queue}" ]; do
			# Removing a trailing /.
			queue="${queue#/}"
			# Pull the first path segment off of queue.
			local segment="${queue%%/*}"
			# If this is the last segment.
			if [[ "${queue}" != */* ]] ; then
				segment="${queue}"
				queue=""
			else
				# Remove that first segment.
				queue="${queue#*/}"
			fi
			local link="${current}/${segment}"
			if [ -h "${link}" ] ; then
				link="$(readlink "${link}")"
				queue="${link}/${queue}"
				if [[ "${link}" == /* ]] ; then
					current=""
				fi
			else
				current="${link}"
			fi
		done

		echo "${current}"
	else
		readlink -f "$1"
	fi
}

readonly ASPECTS_DIR="$(readlink -f "$(dirname "$(get_realpath "${BASH_SOURCE[0]}")")")"
readonly OUTPUT_GROUPS="compdb_files"

readonly WORKSPACE="$(bazel info workspace)"
readonly EXEC_ROOT="$(bazel info execution_root)"
readonly COMPDB_FILE="${WORKSPACE}/compile_commands.json"

readonly QUERY_CMD=(
  bazel query
    --noshow_progress
    --noshow_loading_progress
    'kind("cc_(library|binary|test|inc_library|proto_library)", //...) union kind("objc_(library|binary|test)", //...)'
)

# Clean any previously generated files.
if [[ -e "${EXEC_ROOT}" ]]; then
  find "${EXEC_ROOT}" -name '*.compile_commands.json' -delete
fi

# shellcheck disable=SC2046
bazel build \
  "--override_repository=bazel_compdb=${ASPECTS_DIR}" \
  "--aspects=@bazel_compdb//:aspects.bzl%compilation_database_aspect" \
  "--noshow_progress" \
  "--noshow_loading_progress" \
  "--output_groups=${OUTPUT_GROUPS}" \
  "$@" \
  $("${QUERY_CMD[@]}") > /dev/null

echo "[" > "${COMPDB_FILE}"
find "${EXEC_ROOT}" -name '*.compile_commands.json' -exec bash -c 'cat "$1" && echo ,' _ {} \; \
  >> "${COMPDB_FILE}"
sed -i.bak -e '/^,$/d' -e '$s/,$//' "${COMPDB_FILE}"  # Hygiene to make valid json
sed -i.bak -e "s|__EXEC_ROOT__|${EXEC_ROOT}|" "${COMPDB_FILE}"  # Replace exec_root marker
sed -i.bak -e "s|-isysroot __BAZEL_XCODE_SDKROOT__||" "${COMPDB_FILE}"  # Replace -isysroot __BAZEL_XCODE_SDKROOT__ marker
rm "${COMPDB_FILE}.bak"
echo "]" >> "${COMPDB_FILE}"

# This is for YCM to help find the DB when following generated files.
# The file may be deleted by bazel on the next build.
ln -f -s "${WORKSPACE}/${COMPDB_FILE}" "${EXEC_ROOT}/"
