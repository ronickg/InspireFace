#!/bin/bash
echo "Building InspireFace for iOS devices and simulators"
echo "Current PWD: ${PWD}"

# Get the project root directory
PROJECT_ROOT="$(pwd)"
echo "Project root directory: ${PROJECT_ROOT}"

# Define MNN output directory
MNN_OUTPUT_DIR="$PROJECT_ROOT/3rdparty/MNN/package_scripts/ios/build/output"

# Set version tag
TAG=${VERSION:+-$VERSION}

# Define output directory
OUTPUT_DIR="$PROJECT_ROOT/build"

# Find clang and SDK paths
CLANG=$(xcrun --sdk iphoneos --find clang)
MIN_IOS_VERSION="11.0"
SDK_DEVICE_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
SDK_SIMULATOR_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)

# Set toolchain path
TOOLCHAIN="$PROJECT_ROOT/toolchain/ios.toolchain.cmake"

# Initial cleanup
cleanup() {
    echo "Cleaning up previous build files..."
    mkdir -p "$OUTPUT_DIR"
    rm -rf "$PROJECT_ROOT/build/inspireface-ios-"*
    rm -rf "$PROJECT_ROOT/build/InspireFace.xcframework"
    rm -rf "$PROJECT_ROOT/build/output"
    rm -rf "$PROJECT_ROOT/build/temp-mnn-include-"*
    mkdir -p "$OUTPUT_DIR/output"
}

# Check MNN output and determine headers directory
check_mnn_dependencies() {
    if [ ! -d "$MNN_OUTPUT_DIR" ]; then
        echo "Error: MNN output directory not found at $MNN_OUTPUT_DIR"
        echo "Please build MNN for iOS first using the MNN build scripts."
        exit 1
    fi

    echo "Checking MNN directory structure..."
    if [ -d "$MNN_OUTPUT_DIR/device_arm64/headers" ]; then
        MNN_HEADERS_DIR="headers"
    else
        MNN_HEADERS_DIR="include"
    fi
    echo "Using MNN_HEADERS_DIR=$MNN_HEADERS_DIR"
}

# Prepare MNN headers in the expected structure
prepare_mnn_headers() {
    echo "Preparing MNN headers for building..."
    for arch_dir in device_arm64 simulator_arm64 simulator_x86_64; do
        if [ -d "$MNN_OUTPUT_DIR/$arch_dir/$MNN_HEADERS_DIR" ]; then
            TEMP_INCLUDE_DIR="$PROJECT_ROOT/build/temp-mnn-include-$arch_dir"
            mkdir -p "$TEMP_INCLUDE_DIR/MNN"
            cp -R "$MNN_OUTPUT_DIR/$arch_dir/$MNN_HEADERS_DIR"/* "$TEMP_INCLUDE_DIR/MNN/"

            # Also copy subdirectories like expr and cv if they exist
            [ -d "$MNN_OUTPUT_DIR/$arch_dir/$MNN_HEADERS_DIR/expr" ] &&
                cp -R "$MNN_OUTPUT_DIR/$arch_dir/$MNN_HEADERS_DIR/expr" "$TEMP_INCLUDE_DIR/MNN/"
            [ -d "$MNN_OUTPUT_DIR/$arch_dir/$MNN_HEADERS_DIR/cv" ] &&
                cp -R "$MNN_OUTPUT_DIR/$arch_dir/$MNN_HEADERS_DIR/cv" "$TEMP_INCLUDE_DIR/MNN/"
        else
            echo "Warning: MNN headers for $arch_dir not found"
        fi
    done
}

# Reusable function to handle 'install' directory operations
move_install_files() {
    local root_dir="$1"
    local install_dir="$root_dir/install"

    if [ ! -d "$install_dir" ]; then
        echo "Error: 'install' directory does not exist in $root_dir"
        exit 1
    fi

    find "$root_dir" -mindepth 1 -maxdepth 1 -not -name "install" -exec rm -rf {} +
    mv "$install_dir"/* "$root_dir" 2>/dev/null
    rmdir "$install_dir"
    echo "Files from 'install' moved to $root_dir, and 'install' directory deleted."
}

# Build InspireFace for a specific architecture
build_for_arch() {
    local arch_name=$1
    local platform=$2
    local sdk_path=$3
    local build_dir="$PROJECT_ROOT/build/inspireface-ios-$arch_name$TAG"
    local temp_include_dir="$PROJECT_ROOT/build/temp-mnn-include-$arch_name"

    echo "Building InspireFace for $arch_name on $platform..."

    mkdir -p "$build_dir"
    pushd "$build_dir" >/dev/null || exit 1

    # Check if the MNN directory for this architecture exists
    if [ ! -d "$MNN_OUTPUT_DIR/$arch_name" ]; then
        echo "Error: MNN directory for $arch_name not found"
        popd >/dev/null || exit 1
        return 1
    fi

    # Set IOS_PLATFORM based on architecture
    local ios_platform=""
    local actual_arch=""
    if [ "$arch_name" = "device_arm64" ]; then
        ios_platform="OS64"
        actual_arch="arm64"
    elif [ "$arch_name" = "simulator_x86_64" ]; then
        ios_platform="SIMULATOR64"
        actual_arch="x86_64"
    elif [ "$arch_name" = "simulator_arm64" ]; then
        ios_platform="SIMULATORARM64"
        actual_arch="arm64"
    fi

    # Build using CMake with toolchain
    cmake "$PROJECT_ROOT" \
        -DIOS_3RDPARTY="${MNN_OUTPUT_DIR}/${arch_name}" \
        -DCMAKE_TOOLCHAIN_FILE=${TOOLCHAIN} \
        -DCMAKE_OSX_ARCHITECTURES="${actual_arch}" \
        -DIOS_PLATFORM="${ios_platform}" \
        -DENABLE_BITCODE=0 \
        -DIOS_DEPLOYMENT_TARGET=11.0 \
        -DISF_BUILD_WITH_SAMPLE=OFF \
        -DISF_BUILD_WITH_TEST=OFF \
        -DISF_BUILD_SHARED_LIBS=OFF \
        -DMNN_HEADERS_DIR="${MNN_HEADERS_DIR}" \
        -DMNN_INCLUDE_DIR="${temp_include_dir}" \
        -DMNN_STATIC_PATH="${MNN_OUTPUT_DIR}/${arch_name}"
    # -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
    # -DIOS_PLATFORM="${ios_platform}" \
    # -DIOS_DEPLOYMENT_TARGET="${MIN_IOS_VERSION}" \
    # -DENABLE_BITCODE=0 \
    # -DMNN_HEADERS_DIR="${MNN_HEADERS_DIR}" \
    # -DMNN_INCLUDE_DIR="${temp_include_dir}" \
    # -DMNN_STATIC_PATH="${MNN_OUTPUT_DIR}/${arch_name}" \
    # -DISF_BUILD_WITH_SAMPLE=OFF \
    # -DISF_BUILD_WITH_TEST=OFF \
    # -DISF_BUILD_SHARED_LIBS=OFF

    if [ $? -ne 0 ]; then
        echo "Error: Build configuration failed for $arch_name"
        popd >/dev/null || exit 1
        return 1
    fi

    make -j$(sysctl -n hw.logicalcpu) && make install

    if [ $? -ne 0 ]; then
        echo "Error: Build failed for $arch_name"
        popd >/dev/null || exit 1
        return 1
    fi

    # Handle install directory
    move_install_files "$(pwd)"

    popd >/dev/null || exit 1
    return 0
}

# Process library files and prepare for XCFramework
process_libraries() {
    echo "Processing InspireFace libraries for XCFramework..."

    # Create output structure
    mkdir -p "$OUTPUT_DIR/output/device_arm64/headers"
    mkdir -p "$OUTPUT_DIR/output/simulator_arm64/headers"
    mkdir -p "$OUTPUT_DIR/output/simulator_x86_64/headers"

    # Temp directories for XCFramework creation
    mkdir -p "$OUTPUT_DIR/temp/ios-arm64/Headers"
    mkdir -p "$OUTPUT_DIR/temp/ios-simulator/Headers"

    # Process device_arm64
    lib_path="$PROJECT_ROOT/build/inspireface-ios-device_arm64$TAG/InspireFace/lib/libInspireFace.a"
    header_path="$PROJECT_ROOT/build/inspireface-ios-device_arm64$TAG/InspireFace/include"

    if [ -f "$lib_path" ]; then
        cp "$lib_path" "$OUTPUT_DIR/output/device_arm64/libInspireFace.a"
        cp "$lib_path" "$OUTPUT_DIR/temp/ios-arm64/libInspireFace.a"
        echo "Copied device_arm64 InspireFace library"
    else
        echo "Error: InspireFace library for device_arm64 not found at $lib_path"
        exit 1
    fi

    if [ -d "$header_path" ]; then
        cp -R "$header_path/"* "$OUTPUT_DIR/output/device_arm64/headers/"
        cp -R "$header_path/"* "$OUTPUT_DIR/temp/ios-arm64/Headers/"
        echo "Copied device_arm64 InspireFace headers"
    else
        echo "Error: InspireFace headers for device_arm64 not found at $header_path"
        exit 1
    fi

    # Process simulator_arm64
    lib_path="$PROJECT_ROOT/build/inspireface-ios-simulator_arm64$TAG/InspireFace/lib/libInspireFace.a"
    header_path="$PROJECT_ROOT/build/inspireface-ios-simulator_arm64$TAG/InspireFace/include"

    if [ -f "$lib_path" ]; then
        cp "$lib_path" "$OUTPUT_DIR/output/simulator_arm64/libInspireFace.a"
        echo "Copied simulator_arm64 InspireFace library"
    else
        echo "Error: InspireFace library for simulator_arm64 not found at $lib_path"
        exit 1
    fi

    if [ -d "$header_path" ]; then
        cp -R "$header_path/"* "$OUTPUT_DIR/output/simulator_arm64/headers/"
        echo "Copied simulator_arm64 InspireFace headers"
    else
        echo "Error: InspireFace headers for simulator_arm64 not found at $header_path"
        exit 1
    fi

    # Process simulator_x86_64
    lib_path="$PROJECT_ROOT/build/inspireface-ios-simulator_x86_64$TAG/InspireFace/lib/libInspireFace.a"
    header_path="$PROJECT_ROOT/build/inspireface-ios-simulator_x86_64$TAG/InspireFace/include"

    if [ -f "$lib_path" ]; then
        cp "$lib_path" "$OUTPUT_DIR/output/simulator_x86_64/libInspireFace.a"
        echo "Copied simulator_x86_64 InspireFace library"
    else
        echo "Error: InspireFace library for simulator_x86_64 not found at $lib_path"
        exit 1
    fi

    if [ -d "$header_path" ]; then
        cp -R "$header_path/"* "$OUTPUT_DIR/output/simulator_x86_64/headers/"
        echo "Copied simulator_x86_64 InspireFace headers"
    else
        echo "Error: InspireFace headers for simulator_x86_64 not found at $header_path"
        exit 1
    fi
}

# Create the final XCFramework structure
create_xcframework() {
    echo "Creating universal simulator binary..."

    # Create universal simulator library
    lipo -create \
        "$OUTPUT_DIR/output/simulator_x86_64/libInspireFace.a" \
        "$OUTPUT_DIR/output/simulator_arm64/libInspireFace.a" \
        -output "$OUTPUT_DIR/temp/ios-simulator/libInspireFace.a"

    cp -R "$OUTPUT_DIR/output/simulator_arm64/headers/"* "$OUTPUT_DIR/temp/ios-simulator/Headers/"

    # Verify architecture
    echo "Universal simulator architectures:"
    lipo -info "$OUTPUT_DIR/temp/ios-simulator/libInspireFace.a"

    echo "Creating XCFramework..."
    rm -rf "$OUTPUT_DIR/InspireFace.xcframework"

    xcodebuild -create-xcframework \
        -library "$OUTPUT_DIR/temp/ios-arm64/libInspireFace.a" -headers "$OUTPUT_DIR/temp/ios-arm64/Headers" \
        -library "$OUTPUT_DIR/temp/ios-simulator/libInspireFace.a" -headers "$OUTPUT_DIR/temp/ios-simulator/Headers" \
        -output "$OUTPUT_DIR/InspireFace.xcframework"

    if [ $? -ne 0 ]; then
        echo "Error creating XCFramework. Exiting."
        exit 1
    fi

    # Clean up temporary directories
    rm -rf "$OUTPUT_DIR/temp"
}

# Main execution flow
main() {
    cleanup
    check_mnn_dependencies
    prepare_mnn_headers

    # Build for all architectures
    build_for_arch "device_arm64" "iphoneos" "${SDK_DEVICE_PATH}" || exit 1
    build_for_arch "simulator_x86_64" "iphonesimulator" "${SDK_SIMULATOR_PATH}" || exit 1
    build_for_arch "simulator_arm64" "iphonesimulator" "${SDK_SIMULATOR_PATH}" || exit 1

    process_libraries
    create_xcframework

    echo "✅ Build completed successfully!"
    echo "📦 InspireFace.xcframework successfully created in build directory"
    echo "Individual architecture libraries and headers are available in build/output directory"
}

main
