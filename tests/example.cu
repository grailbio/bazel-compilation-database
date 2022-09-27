// Copyright 2022 Aqrose Technology, Ltd.
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

#ifdef USE_CUDA

#include "example.hpp"
#include <cstdio>

__global__ void kernel() {
  printf("kernel id = %d\n", blockIdx.x * blockDim.x + threadIdx.x);
}

int launch() {
  kernel<<<2, 3>>>();
  return 0;
}

#endif
