#include <hip/hip_fp16.h>
#include <hip/hip_runtime.h>
#include <miopen/miopen.h>

#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

void Check(miopenStatus_t status)
{
    if(status != miopenStatusSuccess)
        throw std::runtime_error(std::string("MIOpen: ") + miopenGetErrorString(status));
}

void Check(hipError_t status)
{
    if(status != hipSuccess)
        throw std::runtime_error(std::string("HIP: ") + hipGetErrorString(status));
}

template <class T>
void CheckConvolution(miopenDataType_t dtype)
{
    miopenHandle_t handle;
    miopenTensorDescriptor_t x_desc, w_desc, y_desc;
    miopenConvolutionDescriptor_t conv_desc;
    Check(miopenCreate(&handle));
    Check(miopenCreateTensorDescriptor(&x_desc));
    Check(miopenCreateTensorDescriptor(&w_desc));
    Check(miopenCreateTensorDescriptor(&y_desc));
    Check(miopenCreateConvolutionDescriptor(&conv_desc));
    Check(miopenSet4dTensorDescriptor(x_desc, dtype, 1, 3, 560, 560));
    Check(miopenSet4dTensorDescriptor(w_desc, dtype, 64, 3, 12, 12));
    Check(miopenInitConvolutionDescriptor(conv_desc, miopenConvolution, 0, 0, 12, 12, 1, 1));

    int n, c, h, w;
    Check(miopenGetConvolutionForwardOutputDim(conv_desc, x_desc, w_desc, &n, &c, &h, &w));
    if(n != 1 || c != 64 || h != 46 || w != 46)
        throw std::runtime_error("Unexpected convolution output shape");
    Check(miopenSet4dTensorDescriptor(y_desc, dtype, n, c, h, w));

    std::vector<T> x(1 * 3 * 560 * 560, static_cast<T>(1.0f));
    std::vector<T> weights(64 * 3 * 12 * 12, static_cast<T>(1.0f / 32.0f));
    std::vector<T> y(n * c * h * w, static_cast<T>(std::numeric_limits<float>::quiet_NaN()));
    T *device_x, *device_w, *device_y;
    Check(hipMalloc(&device_x, x.size() * sizeof(T)));
    Check(hipMalloc(&device_w, weights.size() * sizeof(T)));
    Check(hipMalloc(&device_y, y.size() * sizeof(T)));
    Check(hipMemcpy(device_x, x.data(), x.size() * sizeof(T), hipMemcpyHostToDevice));
    Check(hipMemcpy(device_w, weights.data(), weights.size() * sizeof(T), hipMemcpyHostToDevice));
    Check(hipMemcpy(device_y, y.data(), y.size() * sizeof(T), hipMemcpyHostToDevice));

    // This lookup loads the AI fallback model when the find database is empty.
    miopenConvSolution_t solution;
    std::size_t count = 0;
    Check(miopenConvolutionForwardGetSolution(
        handle, w_desc, x_desc, conv_desc, y_desc, 1, &count, &solution));
    if(count != 1)
        throw std::runtime_error("No convolution solution returned");
    void* workspace = nullptr;
    if(solution.workspace_size != 0)
        Check(hipMalloc(&workspace, solution.workspace_size));
    Check(miopenConvolutionForwardImmediate(handle,
                                           w_desc,
                                           device_w,
                                           x_desc,
                                           device_x,
                                           conv_desc,
                                           y_desc,
                                           device_y,
                                           workspace,
                                           solution.workspace_size,
                                           solution.solution_id));
    Check(hipDeviceSynchronize());
    Check(hipMemcpy(y.data(), device_y, y.size() * sizeof(T), hipMemcpyDeviceToHost));
    // All inputs are 1 and weights are 1/32, so every output is exactly 432/32.
    for(const auto value : y)
        if(!std::isfinite(static_cast<float>(value)) ||
           std::abs(static_cast<float>(value) - 13.5f) > 0.01f)
            throw std::runtime_error("Incorrect convolution output");

    if(workspace)
        Check(hipFree(workspace));
    Check(hipFree(device_y));
    Check(hipFree(device_w));
    Check(hipFree(device_x));
    Check(miopenDestroyConvolutionDescriptor(conv_desc));
    Check(miopenDestroyTensorDescriptor(y_desc));
    Check(miopenDestroyTensorDescriptor(w_desc));
    Check(miopenDestroyTensorDescriptor(x_desc));
    Check(miopenDestroy(handle));
    std::cout << "OK: " << (dtype == miopenFloat ? "FP32" : "FP16")
              << " convolution (1, 64, 46, 46)" << std::endl;
}

int main()
{
    try
    {
        CheckConvolution<float>(miopenFloat);
        CheckConvolution<__half>(miopenHalf);
    }
    catch(const std::exception& error)
    {
        std::cerr << error.what() << std::endl;
        return 1;
    }
}
