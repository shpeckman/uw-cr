# makefile
EXAMPLES := $(wildcard examples/*.cr)

$(EXAMPLES):
	@echo "==> $@"
	@crystal run $@
	@echo
	
.PHONY: all setup setup-refresh clean spec bench examples $(EXAMPLES)

all: setup

setup:
	crystal run tools/lib_setup.cr

setup-refresh:
	crystal run tools/lib_setup.cr -- --refresh

clean:
	crystal run tools/lib_setup.cr -- --clean-only

spec:
	crystal spec

bench:
	crystal run --release --no-debug bench/bench.cr

examples: $(EXAMPLES)