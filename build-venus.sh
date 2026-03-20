name: Build Kernel for Xiaomi 11 (venus)

on:
  workflow_dispatch:  # 支持手动触发

permissions:
  contents: write    # 允许创建 Release 和上传资产

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository (optional, if you have scripts)
        uses: actions/checkout@v4

      # 设置全局变量
      - name: Set variables
        run: |
          echo "DEVICE=venus" >> $GITHUB_ENV
          echo "ANDROID_VERSION=14" >> $GITHUB_ENV
          echo "BASE_PATH=$(pwd)" >> $GITHUB_ENV

      - name: Install build dependencies
        run: |
          sudo apt update -y
          sudo apt install -y elfutils libarchive-tools python3

      - name: Clone libufdt
        run: |
          git clone --branch android14-qpr2-release --depth 1 \
            https://android.googlesource.com/platform/system/libufdt.git libufdt

      - name: Clone AnyKernel3
        run: |
          git clone --depth 1 https://github.com/osm0sis/AnyKernel3 AnyKernel3

      - name: Setup Neutron toolchain
        run: |
          mkdir -p toolchain
          cd toolchain
          curl -LO https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman
          chmod +x antman
          ./antman -S
          ./antman --patch=glibc
          cd ${{ env.BASE_PATH }}

      - name: Clone kernel source (Xiaomi sm8350)
        run: |
          git clone --depth 1 https://github.com/Geeeeeker/android_kernel_xiaomi_sm8350.git kernel

      - name: Add KernelSU (v0.9.5)
        run: |
          cd kernel
          curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s v0.9.5
          cd ${{ env.BASE_PATH }}

      - name: Configure and build kernel
        run: |
          export PATH="${{ env.BASE_PATH }}/toolchain/bin:${PATH}"
          export KBUILD_BUILD_HOST=github
          export KBUILD_BUILD_USER=github
          export ARCH=arm64
          cd kernel

          # 使用 venus_defconfig 替换原有配置
          make CC=clang O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 venus_defconfig

          # 可选：禁用 WERROR 避免因警告中断构建
          sed -i 's/CONFIG_CC_WERROR=y/# CONFIG_CC_WERROR=y/g' out/.config

          make CC=clang O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 -j$(nproc --all)

          cd ${{ env.BASE_PATH }}

      - name: Copy kernel image
        run: |
          cp kernel/out/arch/arm64/boot/Image AnyKernel3/

      - name: Generate dtb and dtbo.img
        run: |
          # 查找所有 dtb 并合并（通常位于 vendor/xiaomi/venus/ 或类似路径）
          dtb_files=$(find kernel/out/arch/arm64/boot/dts -name "*.dtb" | sort)
          if [ -n "$dtb_files" ]; then
            cat $dtb_files > AnyKernel3/dtb
          else
            echo "Warning: No dtb files found"
          fi

          # 生成 dtbo.img
          dtbo_files=$(find kernel/out/arch/arm64/boot/dts -name "*.dtbo" | sort)
          if [ -n "$dtbo_files" ]; then
            python3 libufdt/utils/src/mkdtboimg.py create AnyKernel3/dtbo.img \
              --page_size=4096 $dtbo_files
          else
            echo "Warning: No dtbo files found"
          fi

      - name: Prepare AnyKernel3 package
        run: |
          # 移除 git 元数据
          rm -rf AnyKernel3/.git* AnyKernel3/README.md
          echo "Xiaomi 11 (venus) kernel with KernelSU" > AnyKernel3/README.md

          # 修改 anykernel.sh 以适应自动检测分区
          sed -i 's/do.devicecheck=1/do.devicecheck=0/g' AnyKernel3/anykernel.sh
          sed -i 's!BLOCK=/dev/block/platform/omap/omap_hsmmc.0/by-name/boot;!BLOCK=auto;!g' AnyKernel3/anykernel.sh
          sed -i 's/IS_SLOT_DEVICE=0;/IS_SLOT_DEVICE=auto;/g' AnyKernel3/anykernel.sh

      - name: Package as zip
        run: |
          cd AnyKernel3
          zip -r9 ../AnyKernel3-${{ env.DEVICE }}-${{ env.ANDROID_VERSION }}.zip .
          cd ${{ env.BASE_PATH }}

      - name: Generate timestamp for release tag
        id: timestamp
        run: echo "time=$(date +'%Y%m%d-%H%M%S')" >> $GITHUB_OUTPUT

      - name: Create Release and upload asset
        uses: softprops/action-gh-release@v2
        with:
          files: AnyKernel3-${{ env.DEVICE }}-${{ env.ANDROID_VERSION }}.zip
          tag_name: ${{ env.DEVICE }}-${{ env.ANDROID_VERSION }}-${{ steps.timestamp.outputs.time }}
          name: "Kernel for ${{ env.DEVICE }} (Android ${{ env.ANDROID_VERSION }})"
          body: |
            Built from [Geeeeeker/android_kernel_xiaomi_sm8350](https://github.com/Geeeeeker/android_kernel_xiaomi_sm8350)  
            Configuration: `venus_defconfig`  
            Includes KernelSU v0.9.5  
            Flash via custom recovery (e.g., TWRP) that supports AnyKernel3.
          draft: false
          prerelease: false
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
