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
