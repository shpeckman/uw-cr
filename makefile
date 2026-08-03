# makefile

.PHONY: all spec build bench gen gen-refresh clean fetch-testdata

UCD_VERSION := 17.0.0
TESTDATA := spec/data/GraphemeBreakTest.txt

all: clean gen fetch-testdata spec

spec:
	crystal spec

bench:
	crystal run --release --no-debug bench/bench.cr

gen:
	crystal run tools/gen_tables.cr

gen-refresh:
	crystal run tools/gen_tables.cr -- --refresh

fetch-testdata:
	mkdir -p spec/data
	curl -fsSL "https://www.unicode.org/Public/$(UCD_VERSION)/ucd/auxiliary/GraphemeBreakTest.txt" -o $(TESTDATA)

clean:
	rm -f tools/ucd/*
	rm -f spec/data/*
	rm -f src/uw/*.bin