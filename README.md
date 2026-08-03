# uw-cr

Unicode text measurement for Crystal: display width, grapheme-cluster segmentation, and column-budget truncation. Built for terminals and TUIs where you need to know how many columns a string occupies.

Targets [Unicode 17.0.0](https://www.unicode.org/versions/Unicode17.0.0/) and validates grapheme breaking against the official `GraphemeBreakTest.txt`.

## Features

- **Display width** for single code points, first clusters, and whole strings.
- **Grapheme segmentation** implementing [UAX #29](https://www.unicode.org/reports/tr29/), including Indic conjuncts (GB9c), emoji ZWJ sequences (GB11), and regional-indicator pairs (GB12/13).
- **Truncation** to a column budget that never splits a wide cluster across the boundary.
- **Cluster iterators** over `Slice(UInt32)` and UTF-8 `Bytes`, resettable for reuse.
- **Unicode and Legacy width modes**, plus terminal Mode 2027 negotiation.
- **Zero dependencies.** Property tables are embedded at compile time via a two-stage trie.

## Installation

Add the shard to your `shard.yml`:

```yml
dependencies:
  uw-cr:
    github: shpeckman/uw-cr
```

Then run `shards install`.

## Usage

```cr
require "uw-cr"
```

All entry points accept `String`, UTF-8 `Bytes`, or `Slice(UInt32)` of scalar code points.

### String width

`swidth` measures the total column width of a string.

```cr
UW.swidth("hello")          # => 5
UW.swidth("日本語")          # => 6
UW.swidth("👨‍👩‍👧‍👦")          # => 2
UW.swidth("a\u2764\uFE0Fb")  # => 4  (VS16 promotes the heart to width 2)
```

### Single code point

`width_cp` returns the width of one scalar. Wide characters are `2`, zero-width `0`, and control characters `-1`.

```cr
UW.width_cp('A'.ord.to_u32)     # => 1
UW.width_cp(0x4E00_u32)         # => 2
UW.width_cp(0x0301_u32)         # => 0   (combining acute accent)
UW.width_cp(0x1B_u32)           # => -1  (ESC)
```

### First cluster

`width` measures the first grapheme cluster and reports how much input it consumed. The consumed count is in code points for `Slice(UInt32)` and in bytes for `String`/`Bytes`.

```cr
UW.width("\u00E9x")  # => {1, 2}  (width 1, two bytes consumed)
```

`grapheme_next` returns just the span of the next cluster, useful for stepping through text.

```cr
UW.grapheme_next("e\u0301x")  # => 2  (base + combining mark)
```

### Truncation

`truncate` fits text to a column budget, returning the width used and the offset at which to cut. It never splits a wide cluster across the boundary.

```cr
width, offset = UW.truncate("a\u4E00b", 2)  # => {1, 1}
"a\u4E00b".byte_slice(0, offset)            # => "a"
```

### Cluster iteration

`clusters` returns a resettable iterator yielding a `Span` (`width`, `size`, `kind`) per grapheme cluster.

```cr
UW.clusters("e\u0301x\u4E00").each do |span|
  puts "#{span.width} cols, #{span.size} bytes, #{span.kind}"
end
# 1 cols, 3 bytes, Graphemic
# 1 cols, 1 bytes, Graphemic
# 2 cols, 3 bytes, Graphemic
```

`SpanKind` distinguishes `Graphemic`, `Control`, `CR`, `LF`, `CRLF`, and `Tab` spans, so callers can handle line breaks and tabs however they need.

A single iterator can be reused across buffers with `reset`, avoiding reallocation in hot loops:

```cr
it = UW.clusters("ab")
it.each { |span| ... }
it.reset("\u4E00\u4E01")
it.each { |span| ... }
```

## Width modes

Width comes in two modes, selected through `WidthOpts`.

- **Unicode** (default) applies full [UAX #11](https://www.unicode.org/reports/tr11/) and emoji rules: variation selectors switch presentation, ZWJ sequences coalesce, and regional indicators pair into flags.
- **Legacy** sums per-code-point widths without coalescing, matching terminals that predate grapheme-aware rendering.

```cr
UW.swidth("\u2764\uFE0F", opts: UW::WidthOpts.unicode)  # => 2
UW.swidth("\u2764\uFE0F", opts: UW::WidthOpts.legacy)   # => 1
```

`WidthOpts` also carries a per-cluster width cap (default `2`) that bounds how wide any one cluster can report. Set it to `0` to disable capping.

```cr
opts = UW::WidthOpts.new(UW::WidthMode::Unicode, cap: 0)
UW.swidth("👨‍👩‍👧‍👦", opts: opts)  # sums the full sequence
```

### Terminal Mode 2027

`Config` models [Mode 2027](https://mitchellh.com/writing/grapheme-clusters-in-terminals) negotiation, resolving whether a terminal does grapheme-aware width and producing the matching `WidthOpts`:

```cr
cfg = UW::Config.new(supported: true, state: UW::Mode2027State::Set)
UW.swidth(text, opts: cfg.opts)
```

When Mode 2027 is unsupported or reset, `Config` resolves to Legacy width.

## Encoding policies

The UTF-8 entry points take a `Utf8Policy`:

- `Replace` (default) — malformed bytes become U+FFFD and decoding advances one byte.
- `Strict` — decoding stops at the first malformed byte.

```cr
UW.swidth(bytes, UW::Utf8Policy::Strict)
```

`swidth` and `truncate` additionally take a `CtrlPolicy` for control characters:

- `Skip` (default) — control clusters contribute `0` and measurement continues.
- `Fail` — any control cluster makes the whole call return `-1`.

## Unicode version

```cr
UW.unicode_version  # => "17.0.0"
```

## License

Released under the [MIT License](LICENSE).

Unicode data is derived from the Unicode Character Database under the [Unicode License v3](LICENSE-UNICODE).