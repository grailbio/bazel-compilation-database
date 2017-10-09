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

readonly ASPECTS_DIR="$(dirname "$0")"
readonly ASPECTS_FILE="${ASPECTS_DIR/#.\/}/aspects.bzl"
readonly OUTPUT_GROUPS="compdb_files"

readonly WORKSPACE="$(bazel info workspace)"
readonly EXEC_ROOT="$(bazel info execution_root)"
readonly COMPDB_FILE="${ASPECTS_DIR}/compile_commands.json"

readonly QUERY_CMD=(
  bazel query
    --noshow_progress
    --noshow_loading_progress
    'kind("cc_(library|binary|test|inc_library|proto_library)", //...)'
)

# Clean any previously generated files.
if [[ -e "${EXEC_ROOT}" ]]; then
  find "${EXEC_ROOT}" -name '*.compile_commands.json' -delete
fi

# shellcheck disable=SC2046
bazel build \
  --aspects="${ASPECTS_FILE}"%compilation_database_aspect \
  --noshow_progress \
  --noshow_loading_progress \
  --output_groups="${OUTPUT_GROUPS}" \
  "$@" \
  $("${QUERY_CMD[@]}") > /dev/null

echo "[" > "${COMPDB_FILE}"
find "${EXEC_ROOT}" -name '*.compile_commands.json' -exec bash -c 'cat "$1" && echo ,' _ {} \; \
  >> "${COMPDB_FILE}"
sed -i.bak -e '/^,$/d' -e '$s/,$//' "${COMPDB_FILE}"  # Hygiene to make valid json
sed -i.bak -e "s|__EXEC_ROOT__|${EXEC_ROOT}|" "${COMPDB_FILE}"  # Replace exec_root marker
rm "${COMPDB_FILE}.bak"
echo "]" >> "${COMPDB_FILE}"

ln -f -s "${PWD}/${COMPDB_FILE}" "${WORKSPACE}/"

# This is for YCM to help find the DB when following generated files.
# The file may be deleted by bazel on the next build.
ln -f -s "${PWD}/${COMPDB_FILE}" "${EXEC_ROOT}/"
