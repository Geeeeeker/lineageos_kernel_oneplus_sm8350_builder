#!/bin/bash
set -e  # 遇到错误立即退出

BASE_PATH=$(pwd)
export KBUILD_BUILD_HOST=github
export KBUILD_BUILD_USER=github
export ARCH=arm64

echo ">install tools"
sudo apt update -y
sudo apt install -y elfutils libarchive-tools python3

echo ">clone libufdt"
git clone --branch android14-qpr2-release --depth 1 https://android.googlesource.com/platform/system/libufdt.git libufdt

echo ">clone AnyKernel3"
git clone --depth 1 https://github.com/osm0sis/AnyKernel3 AnyKernel3

echo ">download toolchain"
mkdir -p toolchain
cd toolchain
curl -LO https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman
chmod +x antman
./antman -S
./antman --patch=glibc
cd $BASE_PATH

echo ">clone kernel source"
git clone --depth 1 https://github.com/Geeeeeker/android_kernel_xiaomi_sm8350.git kernel

echo ">add KernelSU"
cd kernel
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s v0.9.5
cd $BASE_PATH

echo ">build kernel"
cd kernel
export PATH="$BASE_PATH/toolchain/bin:${PATH}"
make CC=clang O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 venus_gki_defconfig
sed -i 's/CONFIG_CC_WERROR=y/# CONFIG_CC_WERROR=y/g' out/.config
make CC=clang O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 -j$(nproc --all)
cd $BASE_PATH

cp kernel/out/arch/arm64/boot/Image AnyKernel3/

echo ">create dtb and dtbo.img"
dtb_files=$(find kernel/out/arch/arm64/boot/dts -name "*.dtb" | sort)
if [ -n "$dtb_files" ]; then
    cat $dtb_files > AnyKernel3/dtb
fi

dtbo_files=$(find kernel/out/arch/arm64/boot/dts -name "*.dtbo" | sort)
if [ -n "$dtbo_files" ]; then
    python3 libufdt/utils/src/mkdtboimg.py create AnyKernel3/dtbo.img --page_size=4096 $dtbo_files
fi

echo ">clean AnyKernel3"
rm -rf AnyKernel3/.git* AnyKernel3/README.md
echo "Xiaomi 11 (venus) kernel with KernelSU" > AnyKernel3/README.md
sed -i 's/do.devicecheck=1/do.devicecheck=0/g' AnyKernel3/anykernel.sh
sed -i 's!BLOCK=/dev/block/platform/omap/omap_hsmmc.0/by-name/boot;!BLOCK=auto;!g' AnyKernel3/anykernel.sh
sed -i 's/IS_SLOT_DEVICE=0;/IS_SLOT_DEVICE=auto;/g' AnyKernel3/anykernel.sh

echo ">create zip"
cd AnyKernel3
zip -r9 ../AnyKernel3-venus-14.zip .
cd $BASE_PATH

echo "Done."
