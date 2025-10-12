# SPDX-License-Identifier: GPL-2.0-only

ifeq ($(CONFIG_ARCH_PINEAPPLE), y)
include $(src)/pineapple_gki_defconfig
endif

ccflags-y += -Wmissing-prototypes

ifeq ($(CONFIG_CNSS_OUT_OF_TREE),y)
ccflags-y += -I$(srctree)/techpack/wlan/platform/cnss_utils
ccflags-y += -I$(srctree)/techpack/wlan/platform/inc
else
ccflags-y += -I$(srctree)/drivers/net/wireless/cnss_utils
endif

obj-$(CONFIG_ICNSS2) += icnss2.o

icnss2-y := main.o
icnss2-y += debug.o
icnss2-y += power.o
icnss2-y += genl.o
icnss2-$(CONFIG_ICNSS2_QMI) += qmi.o
