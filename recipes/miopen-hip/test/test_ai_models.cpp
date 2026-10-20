#include <fdeep/fdeep.hpp>

#include <filesystem>
#include <iostream>
#include <stdexcept>

int main(int argc, char* argv[])
{
    if(argc != 2)
        throw std::runtime_error("Expected the MIOpen model directory");

    std::size_t count = 0;
    for(const auto& entry : std::filesystem::directory_iterator(argv[1]))
    {
        const auto& path = entry.path();
        if(path.extension() != ".model" ||
           path.filename().string().find("metadata") != std::string::npos)
            continue;

        std::cout << "Verifying " << path.filename() << std::endl;
        // Verification runs the model's embedded input/output test vectors.
        fdeep::load_model(path.string(), true, fdeep::dev_null_logger);
        ++count;
    }
    if(count == 0)
        throw std::runtime_error("No MIOpen AI models found");
    std::cout << "Verified " << count << " bundled MIOpen AI models" << std::endl;
}
