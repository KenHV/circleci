#! /bin/bash
# Copyright (C) 2020 KenHV

BRANCH=$BRANCH
CHANNEL_ID=$CHAT_ID
CONFIG="vendor/liber-perf_defconfig"
DEVICE="Liber"
JOBS=$(nproc --all)
KBUILD_BUILD_HOST="Kensur"
KBUILD_BUILD_USER="KenHV"
KERNEL_DIR="$HOME/kernel"
TC_PATH="$HOME/toolchains"
TELEGRAM_TOKEN="$BOT_API_KEY"
ZIP_DIR="$HOME/AK3"

# send buildlog
tg_errlog() {
	curl -F document=@"$LOG"  "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument" \
			-F chat_id="$CHANNEL_ID" \
			-F caption="Build ran into errors after $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds."
}

# send zip
tg_pushzip() {
	curl -F document=@"$ZIP"  "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument" \
			-F chat_id="$CHANNEL_ID" \
			-F caption="Build finished after $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds."
}

# send messages
tg_sendinfo() {
	curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
		-d "parse_mode=html" \
		-d text="$1" \
		-d chat_id="$CHANNEL_ID" \
		-d "disable_web_page_preview=true"
}

setup_sources() {
    export PATH="$TC_PATH/clang/clang-r399163/bin:$TC_PATH/aarch64/bin:$TC_PATH/aarch32/bin:$PATH"
    export COMPILER="AOSP Clang and GCC"
    rm -rf "$ZIP_DIR" && git clone https://github.com/KenHV/AnyKernel3 "$ZIP_DIR"
    mkdir -p "$KERNEL_DIR"
    git clone --depth=1 https://"${GITHUB_USER}"@github.com/KenHV/kernel_motorola_sm6150 -b msm-4.14 "$KERNEL_DIR"
    cd "$KERNEL_DIR" || exit
}

build_kernel() {
    BUILD_START=$(date +"%s")
    make O=out ARCH=arm64 -j"$JOBS" "$CONFIG"
    make -j"$JOBS" O=out \
                          ARCH=arm64 \
                          CC=clang \
                          CROSS_COMPILE=aarch64-linux-android- \
                          CROSS_COMPILE_ARM32=arm-linux-androideabi- \
                          CLANG_TRIPLE=aarch64-linux-gnu-fi |& tee -a "$LOG"
    BUILD_END=$(date +"%s")
    DIFF=$(($BUILD_END - $BUILD_START))
}

make_flashable() {
    cd "$ZIP_DIR" || exit
    git clean -fd
    cp "$KERN_IMG" "$ZIP_DIR"/zImage
    ZIP_NAME=Kensur-$DEVICE-$KERN_VER-$COMMIT_SHA.zip
    zip -r9 "$ZIP_NAME" * -x ./.git README.md ./*placeholder
    ZIP=$(find "$ZIP_DIR"/*.zip)
    tg_pushzip
}

mkdir -p "$HOME"/build
export LOG=$HOME/build/log.txt

tg_sendinfo "Triggered build for $DEVICE."
setup_sources

COMMIT=$(git log --pretty=format:'"%h : %s"' -1)
COMMIT_SHA=$(git rev-parse --short HEAD)
CONFIG_PATH=$KERNEL_DIR/arch/arm64/configs/$CONFIG
KERN_IMG=$KERNEL_DIR/out/arch/arm64/boot/Image.gz-dtb
KERN_VER=$(make kernelversion)

tg_sendinfo "Threads: <tt>$JOBS</tt>
Branch: <tt>$BRANCH</tt>
Commit: <tt>$COMMIT</tt>"

build_kernel

# Check if kernel img is there or not and make flashable accordingly

if ! [ -a "$KERN_IMG" ]; then
	tg_errlog
	exit 1
else
	make_flashable
fi

