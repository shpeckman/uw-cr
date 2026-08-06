# makefile

.PHONY: all spec bench gen gen-refresh clean

UCD_VERSION := 17.0.0
AUX_URL     := https://www.unicode.org/Public/$(UCD_VERSION)/ucd/auxiliary
TESTS       := GraphemeBreakTest WordBreakTest LineBreakTest

all: clean gen

spec:
	crystal spec

bench:
	crystal run --release --no-debug bench/bench.cr

gen:
	rm -f tools/ucd/*
	rm -f spec/data/*
	rm -f src/uw/*.bin
	crystal run tools/gen_tables.cr
	mkdir -p spec/data
	for t in $(TESTS); do \
		curl -fsSL "$(AUX_URL)/$$t.txt" -o "spec/data/$$t.txt"; \
	done

gen-refresh:
	rm -f spec/data/*
	rm -f src/uw/*.bin
	crystal run tools/gen_tables.cr -- --refresh
	mkdir -p spec/data
	for t in $(TESTS); do \
		curl -fsSL "$(AUX_URL)/$$t.txt" -o "spec/data/$$t.txt"; \
	done

clean:
	rm -f tools/ucd/*
	rm -f spec/data/*
