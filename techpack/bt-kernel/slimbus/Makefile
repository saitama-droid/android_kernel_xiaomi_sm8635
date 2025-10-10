ccflags-y += -I$(srctree)/$(src)/../include
ccflags-y += -I$(srctree)/$(src)/../btfmcodec/include
#Below src is for BTFM SLAVE CODEC Driver support on LE platform.
bt_fm_slim-objs := btfm_slim.o btfm_slim_codec.o btfm_slim_slave.o
obj-$(CONFIG_BTFM_SLIM) += bt_fm_slim.o
# Below src is for BTFM Driver support based on btfm codec
btfm_slim_codec-objs := btfm_slim.o btfm_slim_hw_interface.o btfm_slim_slave.o
obj-$(CONFIG_SLIM_BTFM_CODEC) += btfm_slim_codec.o
