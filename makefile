# makefile

.PHONY: all setup clean spec bench

all: setup spec

setup:
	crystal run tools/lib_setup.cr

clean:
	crystal run tools/lib_setup.cr -- --clean-only

spec:
	crystal spec

bench:
	crystal run --release --no-debug bench/bench.cr
