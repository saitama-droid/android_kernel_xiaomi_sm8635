# SPDX-License-Identifier: GPL-2.0-only

ccflags-y += -Wmissing-prototypes

ifeq ($(CONFIG_CNSS_OUT_OF_TREE),y)
ccflags-y += -I$(srctree)/techpack/wlan/platform/inc
endif

obj-$(CONFIG_CNSS_GENL) := cnss_nl.o
