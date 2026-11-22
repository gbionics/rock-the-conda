#define ORT_API_MANUAL_INIT
#include <onnxruntime_cxx_api.h>
#include <cstdlib>
#include <iostream>

int main() {
    Ort::InitApi();
    for (const auto& provider : Ort::GetAvailableProviders()) {
        std::cout << provider << '\n';
    }
    return EXIT_SUCCESS;
}
