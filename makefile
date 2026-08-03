# makefile

.PHONY: all spec build bench gen gen-refresh clean fetch-testdata

UCD_VERSION := 17.0.0
TESTDATA := spec/data/GraphemeBreakTest.txt

all: clean gen spec

spec:
	crystal spec

bench:
	crystal run --release --no-debug bench/bench.cr

gen: clean
	crystal run tools/gen_tables.cr
	mkdir -p spec/data
	curl -fsSL "https://www.unicode.org/Public/$(UCD_VERSION)/ucd/auxiliary/GraphemeBreakTest.txt" -o $(TESTDATA)

clean:
	rm -f tools/ucd/*
	rm -f spec/data/*
	rm -f src/uw/*.bin