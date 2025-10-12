# SPDX-License-Identifier: GPL-2.0-only

ifeq ($(CONFIG_ARCH_PINEAPPLE), y)
include $(src)/pineapple_gki_defconfig
endif

ccflags-y += -Wmissing-prototypes

ifeq ($(CONFIG_CNSS_OUT_OF_TREE),y)
ccflags-y += -I$(srctree)/techpack/wlan/platform/inc
ccflags-y += -I$(srctree)/techpack/wlan/platform/cnss_utils
endif

obj-$(CONFIG_WCNSS_MEM_PRE_ALLOC) += cnss_prealloc.o
