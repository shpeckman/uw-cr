# Makefile

.PHONY: spec build gen gen-refresh clean fetch-testdata

UCD_VERSION := 17.0.0
TESTDATA := spec/data/GraphemeBreakTest.txt

spec:
	crystal spec

gen:
	crystal run tools/gen_tables.cr

gen-refresh:
	crystal run tools/gen_tables.cr -- --refresh

fetch-testdata:
	mkdir -p spec/data
	curl -fsSL "https://www.unicode.org/Public/$(UCD_VERSION)/ucd/auxiliary/GraphemeBreakTest.txt" -o $(TESTDATA)

clean:
	rm -f uw