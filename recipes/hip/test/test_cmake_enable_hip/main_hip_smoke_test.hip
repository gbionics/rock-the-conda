// MIT License
//
// Copyright (c) 2015-2023 Advanced Micro Devices, Inc. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// Based on https://github.com/ROCm/rocm-examples/blob/6e8d80a683fc16fe92a8e0d8490286cff67c0582/HIP-Basic/hello_world/main.hip

#include <hip/hip_runtime.h>

#include <iostream>

constexpr int error_exit_code = -1;

#define HIP_CHECK(condition)                                                                \
    {                                                                                       \
        const hipError_t error = condition;                                                 \
        if(error != hipSuccess)                                                             \
        {                                                                                   \
            std::cerr << "An error encountered: \"" << hipGetErrorString(error) << "\" at " \
                      << __FILE__ << ':' << __LINE__ << std::endl;                          \
            std::exit(error_exit_code);                                                     \
        }                                                                                   \
    }

__device__ unsigned int get_thread_idx()
{
    return threadIdx.x;
}

__host__ void print_hello_host()
{
    std::cout << "Hello world from host!" << std::endl;
}

__device__ __host__ void print_hello()
{
    printf("Hello world from device or host!\n");
}

__global__ void helloworld_kernel()
{
    unsigned int thread_idx = get_thread_idx();
    unsigned int block_idx = blockIdx.x;

    print_hello();
    printf("Hello world from device kernel block %u thread %u!\n", block_idx, thread_idx);
}

int main()
{
    print_hello_host();
    print_hello();

    helloworld_kernel<<<dim3(2), dim3(2), 0, hipStreamDefault>>>();
    HIP_CHECK(hipDeviceSynchronize());
}
