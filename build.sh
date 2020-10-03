#! /bin/bash
# Copyright (C) 2020 Starlight
#

export DEVICE="Liber"
export CONFIG="vendor/liber-perf_defconfig"
export JOBS=$(nproc --all)
export CHANNEL_ID="$CHAT_ID"
export TELEGRAM_TOKEN="$BOT_API_KEY"
export TC_PATH="$HOME/toolchains"
export ZIP_DIR="$HOME/AK3"
export IS_MIUI="no"
export KERNEL_DIR="$HOME/kernel"
export KBUILD_BUILD_USER="KenHV"
export GCC_COMPILE="$GCC"
export CLANG_VER="$clang_ver"
export KBUILD_BUILD_HOST="Kensur"

#==============================================================
#===================== Function Definition ====================
#==============================================================
#======================= Telegram Start =======================
#==============================================================

# Upload buildlog to group
tg_erlog()
{
	curl -F document=@"$LOG"  "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument" \
			-F chat_id=$CHANNEL_ID \
			-F caption="Build ran into errors after $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds."
}

# Upload zip to channel
tg_pushzip()
{
	curl -F document=@"$ZIP"  "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument" \
			-F chat_id=$CHANNEL_ID \
			-F caption="Build finished after $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds."
}

# Send Updates
function tg_sendinfo() {
	curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
		-d "parse_mode=html" \
		-d text="${1}" \
		-d chat_id="${CHANNEL_ID}" \
		-d "disable_web_page_preview=true"
}

# Send a sticker
function start_sticker() {
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendSticker" \
        -d sticker="CAACAgUAAxkBAAEBaLBfeFQfSbusJ4dR7d6wyWD6ZjAkFgACNQIAAjHMoyHGbTmtdlKXVxsE" \
        -d chat_id=$CHANNEL_ID
}

#======================= Telegram End =========================
#======================== Clone Stuff ==========================

function clone_tc() {
[ -d ${TC_PATH} ] || mkdir ${TC_PATH}

if [ "$GCC_COMPILE" == "yes" ]; then
	git clone --depth=1 https://github.com/arter97/arm64-gcc ${TC_PATH}/gcc64
	git clone --depth=1 https://github.com/arter97/arm32-gcc ${TC_PATH}/gcc32
	export PATH="${TC_PATH}/gcc64/bin:${TC_PATH}/gcc32/bin:$PATH"
	export STRIP="${TC_PATH}/gcc64/aarch64-elf/bin/strip"
	export COMPILER="Arter97's Latest GCC Compiler"
else
	if [ "$CLANG_VER" == "12" ]; then
		git clone --depth=1 https://github.com/kdrag0n/proton-clang.git ${TC_PATH}/clang
		export PATH="${TC_PATH}/clang/bin:$PATH"
		export STRIP="${TC_PATH}/clang/aarch64-linux-gnu/bin/strip"
		export COMPILER="Kdrag0n's Latest Proton Clang"
	else
        git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9 $HOME/toolchains/aarch64
        git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9 $HOME/toolchains/aarch32
        wget https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master/clang-r399163.tar.gz
        mv clang-r399163.tar.gz $HOME/toolchains
        mkdir $HOME/toolchains/clang
        tar xzf $HOME/toolchains/clang-r399163.tar.gz -C $HOME/toolchains/clang
		export PATH="$TC_PATH/clang/bin:$TC_PATH/aarch64/bin:$TC_PATH/aarch32/bin:$PATH"
		export COMPILER="AOSP Clang and LOS GCC"
	fi
fi

rm -rf $ZIP_DIR && git clone https://github.com/KenHV/AnyKernel3 $ZIP_DIR
}

function clone_kernel(){

mkdir -p $KERNEL_DIR
git clone --depth=1 https://${GITHUB_USER}@github.com/KenHV/kernel_motorola_sm6150 -b msm-4.14 $KERNEL_DIR
cd $KERNEL_DIR

}

#==============================================================
#=========================== Make =============================
#========================== Kernel ============================
#==============================================================

build_kernel() {
DATE=`date`
BUILD_START=$(date +"%s")
make O=out ARCH=arm64 "$CONFIG"

if [ "$GCC_COMPILE" == "yes" ]; then
	make -j$(nproc --all) O=out \
			      ARCH=arm64 \
			      CROSS_COMPILE=aarch64-elf- \
			      CROSS_COMPILE_ARM32=arm-eabi- |& tee -a $LOG
else
	make -j$(nproc --all) O=out \
			      ARCH=arm64 \
                    CC=clang \
                    CROSS_COMPILE="$HOME/toolchains/aarch64/bin/aarch64-linux-android-" \
                    CROSS_COMPILE_ARM32="$HOME/toolchains/aarch32/bin/arm-linux-androideabi-" \
                    CLANG_TRIPLE=aarch64-linux-gnu-fi |& tee -a $LOG
fi

BUILD_END=$(date +"%s")
DIFF=$(($BUILD_END - $BUILD_START))
}

#==================== Make Flashable Zip ======================

function make_flashable() {

if [ "$IS_MIUI" == "yes" ]; then
    for MODULES in $(find "$KERNEL_DIR/out" -name '*.ko'); do
        "${STRIP}" --strip-unneeded --strip-debug "${MODULES}"
        "$KERNEL_DIR/scripts/sign-file" sha512 \
                "$KERNEL_DIR/out/signing_key.priv" \
                "$KERNEL_DIR/out/signing_key.x509" \
                "${MODULES}"
        case ${MODULES} in
                */wlan.ko)
		cp "${MODULES}" "${VENDOR_MODULEDIR}/pronto_wlan.ko"
            ;;
        esac
    done
    echo -e "(i) Done moving wifi modules"
fi

cd $ZIP_DIR
git clean -fd
cp $KERN_IMG $ZIP_DIR/zImage
ZIP_NAME=Kensur-$DEVICE-$KERN_VER-$COMMIT.zip
zip -r9 $ZIP_NAME * -x .git README.md *placeholder
ZIP=$(find $ZIP_DIR/*.zip)
tg_pushzip

}

#========================= Build Log ==========================

mkdir -p $HOME/build
export LOG=$HOME/build/log.txt

#===================== End of function ========================
#======================= definition ===========================

tg_sendinfo "$(echo -e "Triggered build for $DEVICE.")"
clone_tc
clone_kernel

COMMIT=$(git log --pretty=format:'"%h : %s"' -1)
COMMIT_SHA=$(git rev-parse --short HEAD)
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
KERN_IMG=$KERNEL_DIR/out/arch/arm64/boot/Image.gz-dtb
CONFIG_PATH=$KERNEL_DIR/arch/arm64/configs/$CONFIG
VENDOR_MODULEDIR="$ZIP_DIR/modules/vendor/lib/modules"
export KERN_VER=$(echo "$(make kernelversion)")

tg_sendinfo "$(echo -e "Threads: <tt>$JOBS</tt>\n
Branch: <tt>$BRANCH</tt>\n
Commit: <tt>$COMMIT</tt>")"

build_kernel

# Check if kernel img is there or not and make flashable accordingly

if ! [ -a "$KERN_IMG" ]; then
	tg_erlog
	exit 1
else
	make_flashable
fi
