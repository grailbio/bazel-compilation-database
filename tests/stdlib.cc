// Copyright 2024 The Bazel Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Test program to check system includes in YCM semantic completion.
// See https://github.com/grailbio/bazel-compilation-database/issues/36

#include <cstddef>
#include <ctime>
#include <iostream>

int main() {
  std::time_t result = std::time(nullptr);
  std::cout << std::asctime(std::localtime(&result));
  return 0;
}
