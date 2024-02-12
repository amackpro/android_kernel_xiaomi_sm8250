#!/usr/bin/env bash
# shellcheck disable=SC2199
# shellcheck source=/dev/null
#
# Copyright (C) 2020-22 UtsavBalar1231 <utsavbalar1231@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

DEVICE="$1"

if [[ $@ =~ ksu ]]; then
	curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
fi

KBUILD_COMPILER_STRING=$($HOME/tc/clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
KBUILD_LINKER_STRING=$($HOME/tc/clang/bin/ld.lld --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//' | sed 's/(compatible with [^)]*)//')
export KBUILD_COMPILER_STRING
export KBUILD_LINKER_STRING

#
# Enviromental Variables
#

DATE=$(date '+%Y%m%d-%H%M')

# Set our directory
OUT_DIR=out/

if [[ "$2" == "miui" ]]; then
	VERSION="MINAZUKI-MIUI-${DEVICE^^}-${DATE}"
fi

if [[ "$2" == "aosp" ]]; then
	VERSION="MINAZUKI-AOSP-${DEVICE^^}-${DATE}"
fi

if [[ "$2" == "" ]]; then
	VERSION="MINAZUKI-PORTS-${DEVICE^^}-${DATE}"
fi

# Export Zip name
export ZIPNAME="${VERSION}.zip"

# How much kebabs we need? Kanged from @raphielscape :)
if [[ -z "${KEBABS}" ]]; then
    COUNT="$(grep -c '^processor' /proc/cpuinfo)"
    export KEBABS="$((COUNT + 2))"
fi

echo "Jobs: ${KEBABS}"

ARGS="ARCH=arm64 \
O=${OUT_DIR} \
CC=clang \
LD=ld.lld \
AR=llvm-ar \
NM=llvm-nm \
OBJCOPY=llvm-objcopy \
OBJDUMP=llvm-objdump \
STRIP=llvm-strip \
CLANG_TRIPLE=aarch64-linux-gnu- \
CROSS_COMPILE=aarch64-linux-gnu- \
CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
-j${KEBABS}"

dts_source=arch/arm64/boot/dts/vendor/qcom

START=$(date +"%s")

# Set compiler Path
export PATH="$HOME/tc/clang/bin:$PATH"
export LD_LIBRARY_PATH=${HOME}/tc/clang/lib64:$LD_LIBRARY_PATH

echo "------ Starting Compilation ------"

# Make defconfig
make -j${KEBABS} ${ARGS} vendor/"${DEVICE}"_defconfig

if [[ "$2" == "miui" ]]; then
echo " -------MIUI optimization initialized-------"
scripts/config --file out/.config \
    --set-str STATIC_USERMODEHELPER_PATH /system/bin/micd \
    -e BOOT_INFO \
    -e BINDER_OPT \
    -e MIHW
fi

if [[ $@ =~ ksu ]]; then
scripts/config --file out/.config \
    -e KPROBES \
    -e HAVE_KPROBES \
    -e KPROBE_EVENTS \
    -e KSU
fi

if [[ "$2" =~ "aosp" ]]; then
    if [[ "$1" == "alioth" ]]; then
        sed -i 's/<1546>/<155>/g' ${dts_source}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
        sed -i 's/<695>/<70>/g' ${dts_source}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
    fi
    if [[ "$1" == "munch" ]]; then
    	sed -i 's/<1546>/<155>/g' ${dts_source}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
    	sed -i 's/<695>/<70>/g' ${dts_source}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
    fi
fi

# Make olddefconfig
cd ${OUT_DIR} || exit
make -j${KEBABS} ${ARGS} CC="ccache clang" HOSTCC="ccache gcc" HOSTCXX="cache g++" olddefconfig
cd ../ || exit

make -j${KEBABS} ${ARGS} CC="ccache clang" HOSTCC="ccache gcc" HOSTCXX="ccache g++" 2>&1 | tee build.log

if [[ "$2" =~ "aosp"* ]]; then
        git checkout arch/arm64/boot/dts/vendor &>/dev/null
fi

if [[ $@ =~ ksu ]]; then
	git checkout drivers/Makefile &>/dev/null
	git checkout drivers/Kconfig &>/dev/null
	rm -rf KernelSU
	rm -rf drivers/kernelsu
fi

echo "------ Finishing Build ------"

END=$(date +"%s")
DIFF=$((END - START))
if [[ $@ =~ ksu ]]; then
	zipname="${VERSION}-KSU.zip"
else
	zipname="$VERSION.zip"
fi
if [ -f "out/arch/arm64/boot/Image" ] && [ -f "out/arch/arm64/boot/dtbo.img" ] && [ -f "out/arch/arm64/boot/dtb" ]; then
	git clone -q https://github.com/amackpro/AnyKernel3.git -b ${DEVICE}
	cp out/arch/arm64/boot/Image AnyKernel3
	cp out/arch/arm64/boot/dtb AnyKernel3
	cp out/arch/arm64/boot/dtbo.img AnyKernel3
	rm -f *zip
	cd AnyKernel3
	zip -r9 "../${zipname}" * -x '*.git*' README.md *placeholder >> /dev/null
	cd ..
	rm -rf AnyKernel3
	echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
	echo ""
	echo -e ${zipname} " is ready!"
	echo ""
else
	echo -e "\n Compilation Failed!"
fi
