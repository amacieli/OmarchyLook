#!/bin/bash
# Build script for OmarchyLook (Rust + QML)
# Usage: ./build.sh [--release] [--clean] [--dev-setup]

set -e

# Ensure Rust toolchain is available
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect if we're in the project root
if [ ! -f "Cargo.toml" ] || [ ! -d "qml" ]; then
    echo -e "${RED}Error: build.sh must be run from the project root${NC}"
    exit 1
fi

PROJECT_DIR=$(pwd)
BUILD_TYPE="debug"
CLEAN_BUILD=false
DEV_SETUP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --release)
            BUILD_TYPE="release"
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --dev-setup)
            DEV_SETUP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: ./build.sh [--release] [--clean] [--dev-setup]"
            exit 1
            ;;
    esac
done

echo -e "${GREEN}🔨 OmarchyLook Build System${NC}"
echo "Build type: $BUILD_TYPE"
echo "Project dir: $PROJECT_DIR"

# === DEV SETUP ===
if [ "$DEV_SETUP" = true ]; then
    echo -e "\n${YELLOW}📦 Running development setup...${NC}"
    
    # Check for required Qt 6 development files
    if ! pkg-config --exists Qt6Core Qt6Gui Qt6Qml; then
        echo -e "${RED}❌ Qt 6 development files not found${NC}"
        echo "Install with: sudo apt install qt6-base-dev qt6-qml-module-qtquick"
        exit 1
    fi
    
    # Check for Rust
    if ! command -v cargo &> /dev/null; then
        echo -e "${RED}❌ Rust/Cargo not found${NC}"
        echo "Install from: https://rustup.rs/"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Qt 6 development files found${NC}"
    echo -e "${GREEN}✓ Rust toolchain found ($(rustc --version))${NC}"
fi

# === CLEAN ===
if [ "$CLEAN_BUILD" = true ]; then
    echo -e "\n${YELLOW}🧹 Cleaning build artifacts...${NC}"
    cargo clean
    echo -e "${GREEN}✓ Clean complete${NC}"
fi

# === BUILD ===
echo -e "\n${YELLOW}🏗️  Building ($BUILD_TYPE)...${NC}"

if [ "$BUILD_TYPE" = "release" ]; then
    cargo build --release 2>&1 | tee build.log
    BINARY="target/release/omarchy-look"
else
    cargo build 2>&1 | tee build.log
    BINARY="target/debug/omarchy-look"
fi

# Check if build succeeded
if [ ! -f "$BINARY" ]; then
    echo -e "${RED}❌ Build failed. Check build.log for details.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Build successful${NC}"
echo -e "${GREEN}Binary: $(realpath "$BINARY")${NC}"
echo -e "${GREEN}Size: $(du -h "$BINARY" | cut -f1)${NC}"

# === SUMMARY ===
echo -e "\n${GREEN}=== Build Summary ===${NC}"
echo "Output binary: $BINARY"
echo "To run: ./run.sh"
echo "To run with release build: QML_DIR=qml ./run.sh --release"
