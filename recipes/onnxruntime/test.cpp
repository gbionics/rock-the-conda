#define ORT_API_MANUAL_INIT
#include <onnxruntime/onnxruntime_cxx_api.h>
#include <cstdlib>
#include <iostream>

int main() {
    Ort::InitApi();
    const auto providers = Ort::GetAvailableProviders();

    for (const auto& provider : providers) {
        std::cout << provider << '\n';
    }

    return EXIT_SUCCESS;
}
