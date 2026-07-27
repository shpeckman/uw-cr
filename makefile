# Makefile

.PHONY: spec build clean fetch-testdata

UCD_VERSION := 17.0.0
TESTDATA := spec/data/GraphemeBreakTest.txt

spec:
	crystal spec

build:
	crystal build --release src/uw.cr -o uw

fetch-testdata:
	mkdir -p spec/data
	curl -fsSL "https://www.unicode.org/Public/$(UCD_VERSION)/ucd/auxiliary/GraphemeBreakTest.txt" -o $(TESTDATA)

clean:
	rm -f uw