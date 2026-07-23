# Makefile

CC       ?= cc
CSRC     := src/uw
OUT      := ext
# Override the cluster-width cap at build time, e.g. `make UW_CAP=0`.
UW_CAP   ?= 2
CFLAGS   ?= -O2 -fPIC -std=c11
CPPFLAGS := -I$(CSRC) -DUW_CLUSTER_WIDTH_CAP=$(UW_CAP)

.PHONY: all clean

all: $(OUT)/libuw.a

$(OUT):
	mkdir -p $(OUT)

$(OUT)/uw_impl.o: $(CSRC)/uw_impl.c $(CSRC)/uw.h | $(OUT)
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

$(OUT)/libuw.a: $(OUT)/uw_impl.o
	$(AR) rcs $@ $^

clean:
	$(RM) $(OUT)/uw_impl.o $(OUT)/libuw.a