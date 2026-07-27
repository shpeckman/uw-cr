# uw-cr

Unicode display-width measurement and grapheme-cluster segmentation for Crystal, built on Unicode 17.0.0. It answers two questions a terminal or text-layout engine keeps asking: where does one user-perceived character end and the next begin, and how many columns does it occupy?

The core is a streaming UAX #29 grapheme boundary state machine plus a terminal-oriented width accumulator, backed by a compact two-stage lookup table. All state lives in caller-owned structs, so nothing allocates on the hot path and every function is reentrant.

The shard is named `uw-cr`; the module it provides is `UW`.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  uw-cr:
    github: shpeckman/uw-cr
```

Then run `shards install` and require it:

```crystal
require "uw-cr"
```

## Quick start

```crystal
require "uw-cr"

UW.swidth("héllo")        # => 5   whole-string column width
UW.swidth("a\u4E00b")     # => 4   narrow + wide CJK + narrow
UW.width_cp(0x4E00_u32)   # => 2   one code point
UW.width_cp(0x1B_u32)     # => -1  a control character

# First grapheme of a string: its width and the bytes it spans.
UW.width("\u{1F468}\u200D\u{1F469}")  # => {2, 11}  emoji ZWJ sequence

# Byte length of the next grapheme, for iteration.
UW.grapheme_next("\u{1F1E6}\u{1F1E7}xy")  # => 8   a two-code-point flag
```

## Concepts

A **grapheme cluster** is what a reader thinks of as a single character: a base letter plus its combining marks, an emoji built from several code points joined by zero-width joiners, a regional-indicator pair that renders as one flag. Splitting text into clusters is governed by the rules in Unicode Annex #29.

**Display width** is how many terminal columns a cluster occupies: 0 for combining marks and other zero-width code points, 1 for ordinary characters, 2 for wide CJK and emoji. `uw-cr` reports `-1` for control characters so callers can decide how to treat them.

## API

Every function comes in three input flavors: a `String`, a `Bytes` (raw UTF-8), or a `Slice(UInt32)` (decoded code points). String and byte forms take an optional `Utf8Policy` for malformed input.

### Whole-string width

```crystal
UW.swidth(text, ctrl = CtrlPolicy::Skip)                    # Slice(UInt32)
UW.swidth(text, upolicy = Utf8Policy::Replace,
                ctrl = CtrlPolicy::Skip)                    # String / Bytes
```

Sums the width of every grapheme in the string. This is the `wcswidth` analog. The `ctrl` policy decides what a control character does: `Skip` contributes 0 and keeps going (permissive); `Fail` makes the whole call return `-1` (POSIX semantics).

```crystal
UW.swidth("a\tb")                              # => 2   tab skipped
UW.swidth("a\tb", ctrl: UW::CtrlPolicy::Fail)  # => -1
```

### Single-cluster width

```crystal
UW.width(text, policy = Utf8Policy::Replace)  # => {width, consumed}
```

Measures exactly the first grapheme and reports how many code units it spanned, so you can walk a buffer cluster by cluster:

```crystal
bytes = "café".to_slice
offset = 0
while offset < bytes.size
  w, n = UW.width(bytes[offset, bytes.size - offset])
  # ... use w ...
  break if n == 0
  offset += n
end
```

### Grapheme iteration

```crystal
UW.grapheme_next(text, policy = Utf8Policy::Replace)  # => consumed
```

Returns just the code-unit length of the next grapheme (the `consumed` half of `width`). Returns 0 for empty input; under `Utf8Policy::Replace` the byte form always advances at least one byte.

### Per-code-point width

```crystal
UW.width_cp(cp : UInt32)  # => 0, 1, 2, or -1
```

The width of a single code point in isolation, ignoring clustering. `-1` marks a control character.

### Streaming primitives

For driving segmentation directly off an input stream — for instance a terminal read loop that spans buffer boundaries — use the state machine and accumulator directly. Both are `struct`s and hold all their state internally.

```crystal
st = UW::State.new
cl = UW::Cluster.new

"e\u0301".each_char do |ch|
  cp = ch.ord.to_u32
  if st.grapheme_break(cp) && cl.started
    # a boundary fell before cp: flush cl.display_width, then start fresh
    cl.reset
  end
  cl.push(cp)
end
cl.display_width  # => 1   "e" plus a combining acute is one narrow cluster
```

`State#grapheme_break(cp)` returns `true` when a cluster boundary falls immediately before `cp`. `Cluster#push(cp)` accumulates a code point into the current cluster and `Cluster#display_width` reports the result. Call `#reset` on either to reuse it. A persistent `State` segments correctly across separate reads.

### Policies

```crystal
UW::CtrlPolicy::Skip   # controls contribute 0 to string width (default)
UW::CtrlPolicy::Fail   # any control makes swidth return -1

UW::Utf8Policy::Replace # malformed bytes become U+FFFD, advance one byte (default)
UW::Utf8Policy::Strict  # stop at the first malformed sequence
```

The UTF-8 decoder never reads past the length you give it, and rejects overlong encodings, surrogates, and out-of-range values.

### Version metadata

```crystal
UW::VERSION            # => "2.0.0"    the shard version
UW.unicode_version     # => "17.0.0"   the UCD version the tables were built from
```

### Internal symbols

The packed lookup-table internals — the `UW::Props` accessors and the `GCB_*` / `INCB_*` / `VS*` constants — are `protected`/`private` and cannot be reached from outside the module. The functions above are the entire public surface.

## Width policy

Cluster width follows the conventions most modern terminals share:

- A base character plus its combining marks is the width of the base.
- A regional-indicator pair (a flag) is width 2.
- A variation selector promotes or demotes a narrow emoji base: `U+FE0F` (emoji presentation) makes it width 2, `U+FE0E` (text presentation) makes it width 1.
- By default a cluster's width is capped at 2 (the "Mode 2027" behavior of wezterm, ghostty, and foot). To report the base character's own width instead with no cap, define the cap as 0 before requiring the library:

  ```crystal
  module UW
    CLUSTER_WIDTH_CAP = 0
  end
  require "uw-cr"
  ```

  The cap resolves at compile time, so it costs nothing at runtime.

## How it works

Each code point maps to a packed 16-bit property via a two-stage trie: a 4352-entry stage-1 index selects one of 123 deduplicated 256-entry stage-2 blocks. The packed value carries the width, the grapheme-cluster-break class, the Extended_Pictographic and emoji-presentation flags, and the Indic_Conjunct_Break class. Lookups are two array reads.

The tables ship as little-endian binary blobs (`src/uw/stage1.bin`, `src/uw/stage2.bin`) embedded at compile time and decoded once at load. This keeps compile times and memory low compared to a multi-thousand-element array literal. See `AGENT.md` for the packed format and derivation.

## Regenerating the tables

The tables are generated from the raw Unicode Character Database. To rebuild them (for a UCD update, or to audit the derivation):

```
make gen              # uses cached UCD files in tools/ucd/, downloads if absent
make gen-refresh      # re-downloads the UCD sources first
```

The generator (`tools/gen_tables.cr`) fetches five UCD files — `UnicodeData.txt`, `EastAsianWidth.txt`, `GraphemeBreakProperty.txt`, `emoji-data.txt`, and `DerivedCoreProperties.txt` — computes the packed property for every code point, builds the deduplicated trie, and writes both blobs plus `src/uw/tables.cr`. Running it reproduces the committed tables byte-for-byte.

The packed width is derived in this precedence: general category `Cc` is a control (`-1`); a regional indicator is width 1 (the flag pairing to 2 happens during clustering); a code point whose grapheme-break class is Extend, ZWJ, Prepend, or SpacingMark, or whose category is `Cf`, is width 0; an East-Asian Wide or Fullwidth code point, or one with default emoji presentation, is width 2; everything else is width 1.

To target a different UCD version, edit `UCD_VERSION` at the top of the generator.

## Testing

```
make spec
```

The suite validates segmentation against the authoritative `GraphemeBreakTest.txt` from the UCD, checking the break decision at every position of all 766 official test cases, and cross-checks the width path against the same data. Refresh the test file with `make fetch-testdata`.

## Requirements

Crystal ≥ 1.21.0. No third-party dependencies. The table loader is endianness-correct, so it runs on big-endian targets as well.

## License

MIT — see `LICENSE`.

The Unicode data tables under `src/uw/` and the bundled `spec/data/GraphemeBreakTest.txt` are derived from the Unicode Character Database and are additionally subject to the [Unicode License v3](https://www.unicode.org/license.txt).