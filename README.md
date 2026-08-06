# uw-cr

Unicode text measurement and segmentation for Crystal: display width, grapheme clusters, word, sentence, and line boundaries, column-budget truncation, and word wrapping. Built for terminals and TUIs where you need to know how many columns a string occupies and where it is allowed to break.

Targets [Unicode 17.0.0](https://www.unicode.org/versions/Unicode17.0.0/) and validates grapheme, word, sentence, and line breaking against the official `GraphemeBreakTest.txt`, `WordBreakTest.txt`, `SentenceBreakTest.txt`, and `LineBreakTest.txt`.

## Features

- **Display width** for single code points, first clusters, and whole strings.
- **Grapheme segmentation** implementing [UAX #29](https://www.unicode.org/reports/tr29/), including Indic conjuncts (GB9c), emoji ZWJ sequences (GB11), and regional-indicator pairs (GB12/13).
- **Word segmentation** implementing [UAX #29](https://www.unicode.org/reports/tr29/) word boundaries, including numeric and letter-internal punctuation.
- **Sentence segmentation** implementing [UAX #29](https://www.unicode.org/reports/tr29/) sentence boundaries, including abbreviation and lowercase-continuation handling.
- **Line breaking** implementing [UAX #14](https://www.unicode.org/reports/tr14/), distinguishing mandatory breaks from opportunities.
- **Word wrapping** to a column budget, with optional hard-breaking of overlong words.
- **Truncation** to a column budget that never splits a wide cluster across the boundary.
- **Cluster iterators** over `Slice(UInt32)` and UTF-8 `Bytes`, resettable for reuse.
- **Unicode and Legacy width modes**, plus terminal Mode 2027 negotiation.
- **East-Asian ambiguous width**, opt-in, for terminals that render ambiguous characters double-wide.
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
UW.grapheme_next("e\u0301x")  # => 3  (base + combining mark, counted in bytes)
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

### Word segmentation

`words` splits text at UAX #29 word boundaries, yielding a `WordSpan` (`width`, `size`) per segment. Separators are returned as their own spans, so the sizes always tile the input.

```cr
UW.words("Hi there!").each do |w|
  puts w.size
end
# 2  1  5  1

widths = [] of Int32
UW.words("\u65E5\u672C ab").each { |w| widths << w.width }
widths  # => [2, 2, 1, 2]
```

`word_next` returns the span of the first word, which is useful for stepping a cursor.

```cr
UW.word_next("can't stop")  # => 5  (the apostrophe stays inside the word)
UW.word_next("3.14 pie")    # => 4  (the decimal point does not split the number)
```

### Sentence segmentation

`sentences` splits text at UAX #29 sentence boundaries, yielding a `SentenceSpan` (`width`, `size`) per sentence. Trailing separators and spaces stay with the sentence they follow, so the sizes always tile the input.

```cr
UW.sentences("Hello world. This is next.").each do |s|
  puts s.size
end
# 13  13
```

`sentence_next` returns the span of the first sentence, which is useful for stepping through a paragraph.

```cr
UW.sentence_next("The cat sat. The dog ran.")  # => 13  (through the space after the period)
UW.sentence_next("etc. and so on")             # => 14  (a lowercase word continues the sentence)
```

Boundary detection follows the algorithm, not an abbreviation dictionary: a period followed by a space and a capital letter is treated as a break, so `"Dr. Smith"` splits after `"Dr. "`.

### Line breaking

`line_breaks` yields a `BreakSpan` (`width`, `size`, `mandatory`) for each segment ending at a break opportunity. Trailing spaces stay with the segment they follow, matching UAX #14.

```cr
off = 0
UW.line_breaks("ab cd").each do |b|
  puts "ab cd".byte_slice(off, b.size)
  off += b.size
end
# "ab "
# "cd"
```

`mandatory` marks a hard break: a line feed, carriage return, next line, or the end of text.

```cr
flags = [] of Bool
UW.line_breaks("a\nb").each { |b| flags << b.mandatory }
flags  # => [true, true]
```

`line_break_next` returns the offset of the first opportunity.

```cr
UW.line_break_next("ab cd")  # => 3
```

### Wrapping

`wrap` fits text to a column budget, yielding a `Line` (`offset`, `size`, `width`, `mandatory`). Lines are cut at UAX #14 opportunities, trailing whitespace is trimmed, and the reported `width` excludes it.

```cr
text = "The quick brown fox jumps over the lazy dog"
UW.wrap(text, 12).each do |line|
  puts text.byte_slice(line.offset, line.size)
end
# The quick
# brown fox
# jumps over
# the lazy dog
```

A word wider than the whole budget is hard-broken at cluster boundaries so it can never overflow.

```cr
UW.wrap("supercalifragilistic ok", 8)
# "supercal"  "ifragili"  "stic ok"
```

`WrapOpts` controls that behaviour, along with trimming and the underlying width mode. A budget of `0` or less disables width wrapping while still honouring hard breaks.

```cr
opts = UW::WrapOpts.new.with_break_overlong(false).with_trim(false)
UW.wrap(text, 12, opts: opts)
```

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

### East-Asian ambiguous width

[UAX #11](https://www.unicode.org/reports/tr11/) marks some characters as *ambiguous*: narrow in a Western context but wide in an East-Asian one. They measure as width `1` by default. Setting `ambiguous_wide` promotes them to `2`, matching terminals configured for CJK rendering. It composes with either width mode.

```cr
wide = UW::WidthOpts.unicode.with_ambiguous_wide(true)

UW.swidth("\u00A7")               # => 1  (section sign, narrow by default)
UW.swidth("\u00A7", opts: wide)   # => 2  (widened)

UW.width_cp(0x2190_u32, wide)     # => 2  (leftwards arrow)
```

Only ambiguous characters are affected; intrinsically wide, narrow, and zero-width characters keep their width. The flag also feeds `width`, `truncate`, and the cluster iterators, so a promoted cluster is never split across a column budget.

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