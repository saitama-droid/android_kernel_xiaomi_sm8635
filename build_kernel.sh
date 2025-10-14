#!/bin/bash
set -e

# Configuration
DIR=$(readlink -f .)
MAIN=$(readlink -f ${DIR}/..)
KERNEL_DEFCONFIG=peridot_defconfig
CLANG_DIR="$MAIN/toolchains/clang"
KERNEL_DIR=$(pwd)
OUT_DIR="$KERNEL_DIR/out"
ZIMAGE_DIR="$OUT_DIR/arch/arm64/boot"
DTB_DTBO_DIR="$ZIMAGE_DIR/dts/vendor/qcom"
BUILD_START=$(date +"%s")

# Function to check for existing Clang
check_clang() {
    if [ -d "$CLANG_DIR" ] && [ -f "$CLANG_DIR/bin/clang" ]; then
        export PATH="$CLANG_DIR/bin:$PATH"
        export KBUILD_COMPILER_STRING="$($CLANG_DIR/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"
        echo "Found existing Clang: $KBUILD_COMPILER_STRING"
        return 0
    fi
    return 1
}

# Install Clang if needed
if ! check_clang; then
    echo "No valid Clang found. Installing..."
    echo "1. AOSP Clang (clang-r487747c)"
    echo "2. ZyC Clang 22.0"
    read -p "Choose [1-2]: " clang_choice

    case "$clang_choice" in
        1)
            CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android14-release/clang-r487747c.tar.gz"
            ARCHIVE_NAME="clang.tar.gz"
            mkdir -p "$CLANG_DIR"
            wget -P "$MAIN" "$CLANG_URL" -O "$MAIN/$ARCHIVE_NAME" || exit 1
            tar -xf "$MAIN/$ARCHIVE_NAME" -C "$CLANG_DIR" --strip-components=1 || exit 1
            rm -f "$MAIN/$ARCHIVE_NAME"
            ;;
        2)
            CLANG_URL="https://github.com/ZyCromerZ/Clang/releases/download/22.0.0git-20250924-release/Clang-22.0.0git-20250924.tar.gz"
            ARCHIVE_NAME="clang.tar.gz"
            mkdir -p "$CLANG_DIR"
            wget -P "$MAIN" "$CLANG_URL" -O "$MAIN/$ARCHIVE_NAME" || exit 1
            tar -xf "$MAIN/$ARCHIVE_NAME" -C "$CLANG_DIR" || exit 1
            rm -f "$MAIN/$ARCHIVE_NAME"
            ;;
        *)
            echo "Invalid choice. Exiting..."
            exit 1
            ;;
    esac

    if ! check_clang; then
        echo "Clang installation failed. Exiting..."
        exit 1
    fi
fi

# Set up toolchain
export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

# Start build process
echo "**** Building with $KBUILD_COMPILER_STRING ****"
echo "**** Defconfig: $KERNEL_DEFCONFIG ****"

# Audio module configuration
export MODNAME=audio_dlkm
export BOARD_PLATFORM=pineapple
export TARGET_BOARD_PLATFORM=pineapple
export CONFIG_SND_SOC_PINEAPPLE=m
export CONFIG_SND_SOC_QDSP6V2=m

# BT module configuration
export CONFIG_MSM_BT_POWER=m
export CONFIG_BTFM_SLIM=m
export CONFIG_BT_HW_SECURE_DISABLE=y

# Build kernel
make O="$OUT_DIR" CC=clang LLVM=1 LLVM_IAS=1 KCFLAGS="-w" $KERNEL_DEFCONFIG || exit 1
make -j$(nproc --all) O="$OUT_DIR" CC=clang LLVM=1 LLVM_IAS=1 KCFLAGS="-w" || exit 1

# Build modules
BUILD_HAS_MODULES=$(grep "=m" "$OUT_DIR/.config" | wc -l)
if [ $BUILD_HAS_MODULES -gt 0 ]; then
    echo "Building modules..."
    make -j$(nproc --all) O="$OUT_DIR" CC=clang LLVM=1 LLVM_IAS=1 KCFLAGS="-w" modules || exit 1

    # Install modules to temporary directory
    MODULES_DIR="$OUT_DIR/modules_temp"
    rm -rf "$MODULES_DIR"
    mkdir -p "$MODULES_DIR"
    make O="$OUT_DIR" CC=clang LLVM=1 LLVM_IAS=1 KCFLAGS="-w" INSTALL_MOD_PATH="$MODULES_DIR" INSTALL_MOD_STRIP=1 modules_install || exit 1

    # Clean up symlinks
    find "$MODULES_DIR" -type l -delete
fi

# Clean up old kernel zip files
echo "Cleaning up old kernel zip files..."
find "$KERNEL_DIR" -maxdepth 1 -type f -name "OSS-Peridot-*.zip" -exec rm -v {} \;

# Create temporary anykernel directory
TIME=$(date "+%Y%m%d-%H%M%S")
TEMP_ANY_KERNEL_DIR="$KERNEL_DIR/anykernel_temp"
rm -rf "$TEMP_ANY_KERNEL_DIR"

# Clone entire anykernel directory
echo "Cloning anykernel directory..."
if [ -d "$KERNEL_DIR/anykernel" ]; then
    cp -r "$KERNEL_DIR/anykernel" "$TEMP_ANY_KERNEL_DIR"
else
    echo "Error: anykernel directory not found!"
    exit 1
fi

# Copy kernel image
if [ -f "$ZIMAGE_DIR/Image.gz-dtb" ]; then
    cp -v "$ZIMAGE_DIR/Image.gz-dtb" "$TEMP_ANY_KERNEL_DIR/"
elif [ -f "$ZIMAGE_DIR/Image.gz" ]; then
    cp -v "$ZIMAGE_DIR/Image.gz" "$TEMP_ANY_KERNEL_DIR/"
elif [ -f "$ZIMAGE_DIR/Image" ]; then
    cp -v "$ZIMAGE_DIR/Image" "$TEMP_ANY_KERNEL_DIR/"
fi

# Handle module separation based on system_dlkm.txt and vendor_dlkm.txt
if [ $BUILD_HAS_MODULES -gt 0 ]; then
    echo "Preparing module directories..."

    # Create both _modules_system and _modules_vendor directories
    mkdir -p "$TEMP_ANY_KERNEL_DIR/_modules_system"
    mkdir -p "$TEMP_ANY_KERNEL_DIR/_modules_vendor"

    # Read system module list
    if [ -f "$KERNEL_DIR/system_dlkm.txt" ]; then
        echo "Reading system_dlkm.txt..."
        SYSTEM_MODULES=$(grep "\.ko$" "$KERNEL_DIR/system_dlkm.txt" | tr '\n' ' ')
    else
        echo "Warning: system_dlkm.txt not found!"
        SYSTEM_MODULES=""
    fi

    # Read vendor module list
    if [ -f "$KERNEL_DIR/vendor_dlkm.txt" ]; then
        echo "Reading vendor_dlkm.txt..."
        VENDOR_MODULES=$(grep "\.ko$" "$KERNEL_DIR/vendor_dlkm.txt" | tr '\n' ' ')
    else
        echo "Warning: vendor_dlkm.txt not found!"
        VENDOR_MODULES=""
    fi

    # Find all built modules
    echo "Sorting modules..."
    system_count=0
    vendor_count=0
    unclassified_count=0

    find "$MODULES_DIR/lib/modules" -name "*.ko" | while read -r module_path; do
        module_name=$(basename "$module_path")
        
        # Check if module is in system list
        if echo "$SYSTEM_MODULES" | grep -qw "$module_name"; then
            cp -v "$module_path" "$TEMP_ANY_KERNEL_DIR/_modules_system/"
            system_count=$((system_count + 1))
        # Check if module is in vendor list
        elif echo "$VENDOR_MODULES" | grep -qw "$module_name"; then
            cp -v "$module_path" "$TEMP_ANY_KERNEL_DIR/_modules_vendor/"
            vendor_count=$((vendor_count + 1))
        else
            # Default to vendor if not in any list
            echo "Warning: $module_name not in any list, defaulting to vendor"
            cp -v "$module_path" "$TEMP_ANY_KERNEL_DIR/_modules_vendor/"
            unclassified_count=$((unclassified_count + 1))
        fi
    done

    echo "=========================================="
    echo "Module Distribution Summary:"
    echo "  System modules: $(ls -1 "$TEMP_ANY_KERNEL_DIR/_modules_system" 2>/dev/null | wc -l)"
    echo "  Vendor modules: $(ls -1 "$TEMP_ANY_KERNEL_DIR/_modules_vendor" 2>/dev/null | wc -l)"
    echo "=========================================="
    
    # Show what's in each directory
    echo "System modules (_modules_system):"
    ls -lh "$TEMP_ANY_KERNEL_DIR/_modules_system" 2>/dev/null || echo "  (empty)"
    
    echo ""
    echo "Vendor modules (_modules_vendor):"
    ls -lh "$TEMP_ANY_KERNEL_DIR/_modules_vendor" 2>/dev/null || echo "  (empty)"
fi

# Create zip file in kernel root directory
echo "Creating zip package..."
ZIP_NAME="OSS-Peridot-$TIME.zip"
cd "$TEMP_ANY_KERNEL_DIR"
zip -r9 "$KERNEL_DIR/$ZIP_NAME" ./*
cd ..

# Clean up temporary directory
rm -rf "$TEMP_ANY_KERNEL_DIR"

BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
echo -e "\n=========================================="
echo "Build completed in $((DIFF / 60))m $((DIFF % 60))s"
echo "Final zip: $KERNEL_DIR/$ZIP_NAME"
echo "Zip size: $(du -h "$KERNEL_DIR/$ZIP_NAME" | cut -f1)"
echo "=========================================="
