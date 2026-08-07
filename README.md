# uw-cr

Unicode text measurement and segmentation for Crystal (UCD 17.0.0): display width, grapheme clusters (UAX #29), line breaks (UAX #14), and column mapping for terminals.

Backed by a two-stage property trie generated from the UCD. Works on `String`, `Bytes` (UTF-8), and `Slice(UInt32)` (UTF-32). No hot-path allocation.

## Install

```yaml
dependencies:
  uw-cr:
    github: shpeckman/uw-cr
```

```sh
make setup   # download UCD 17.0.0, build the tables
make spec    # verify against GraphemeBreakTest.txt + LineBreakTest.txt
make bench   # run benchmarking
```

`make spec` caches the test files under `$XDG_CACHE_HOME/uw-cr/<version>` (falling back to `~/.cache`).

## Overview

This library answers measurement questions about Unicode text the way a terminal sees it: in display columns and grapheme clusters, not code points. Reach for it when you need to

- measure how many columns a string occupies (`swidth`),
- fit text into a fixed width without splitting a glyph (`truncate`, `slice_cols`),
- slice a horizontally-scrolled line to a viewport (`slice_cols`),
- place a cursor by column or map a click back to a byte offset (`offset_to_col`, `col_to_offset`),
- walk grapheme clusters or find wrap points (`clusters`, `line_breaks`).

Everything below is organized by the task you're trying to do. The [API summary](#api-summary) at the end is the flat reference.

## Conventions

**Widths.** `0` for combining marks and zero-width formatting, `1` narrow, `2` wide (CJK, emoji presentation), `-1` control. Per-string totals (`swidth`) never return `-1` under the default control policy — controls are skipped.

**Sizes are code units.** Every `size` / offset / consumed count is in the units of the buffer you passed: **bytes** for `String` and `Bytes`, **`UInt32` elements** for `Slice(UInt32)`. A `slice_cols` result on a `String` is a byte range; pass it straight to `String#byte_slice`.

**Columns are absolute and half-open.** Wherever a function takes a column range it means `[start_col, end_col)` as absolute columns from the start of the string — not a start plus a width. To slice a width-`w` window starting at scroll offset `x`, pass `start_col: x, end_col: x + w`.

**Encoding policy.** UTF-8 paths take a `Utf8Policy`: `Replace` (default) treats each bad byte as U+FFFD and advances one byte; `Strict` stops at the first invalid byte. On `String`/`Bytes` overloads it is the parameter named `policy`, passed positionally right after the buffer.

## Measuring width

`swidth` totals a string; `width` measures just the first cluster and tells you how far it reached.

```crystal
UW.swidth("hello")                 # => 5
UW.swidth("\u65E5\u672C\u8A9E")    # => 6   three wide CJK
UW.swidth("\u2764\uFE0F")          # => 2   heart + VS16 → emoji presentation
UW.width_cp('A'.ord.to_u32)        # => 1
UW.width_cp(0x1B_u32)              # => -1  control

w, consumed = UW.width("\u00E9x")  # => {1, 2}   first cluster is é, 2 bytes
```

Edge cases: `swidth("")` is `0`. `width("")` is `{0, 0}`. `width_cp` above the assigned range (`>= 0x110000`) is `0`. On the `Bytes`/`String` path under `Strict`, `width` stops at the first bad byte and reports the bytes consumed up to it.

### Controls in a total

`CtrlPolicy` decides what `swidth` does when it meets a control: `Skip` (default) omits it and keeps summing; `Fail` collapses the whole total to `-1`. On the UTF-32 path `ctrl` is the first positional argument; on `String`/`Bytes` it comes after `policy`, so pass it by name.

```crystal
UW.swidth(cps, UW::CtrlPolicy::Fail)          # UTF-32: positional
UW.swidth("a\eb", ctrl: UW::CtrlPolicy::Fail) # => -1
UW.swidth("a\eb")                             # => 2   ESC skipped
```

### The cluster width cap

An unbounded ZWJ sequence renders as one double-wide cell in a terminal, so a cluster's width is capped at `CLUSTER_WIDTH_CAP` (2). A cap of `0` disables the ceiling and sums the true per-codepoint width.

```crystal
family = "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}"
UW.swidth(family)                                          # => 2   capped
UW.swidth(family, opts: UW::WidthOpts.unicode.with_cap(0)) # => 8   uncapped
```

## Fitting text to a width

### Truncate to a budget

`truncate` returns the largest prefix that fits in `max_cols` without splitting a cluster, as `{width_used, cut_offset}`. It never overshoots: a wide cluster that would cross the boundary is left out entirely.

```crystal
width, offset = UW.truncate("\u65E5\u672C\u8A9E is fun", 6)
# => {6, 9}   three CJK fill exactly 6 cols, cut at byte 9

UW.truncate("a\u4E00b", 2)   # => {1, 1}   'a' fits, 一 would overflow → stop
UW.truncate("a\u4E00b", 0)   # => {0, 0}   non-positive budget
```

`cut_offset` is a byte offset on `String`/`Bytes`, an element index on UTF-32 — slice with it directly.

### Slice a column window (scrolling / clipping)

`slice_cols` is the function you want for rendering one line of a scrollable, clipped region. Given an absolute column range `[start_col, end_col)`, it returns a `ColSlice`:

- `offset` / `size` — the byte (or element) range of the fully-visible clusters inside the window,
- `start_col` / `end_col` — the resolved bounds (echoed back after clamping),
- `pad_left` / `pad_right` — spaces to emit where a **wide cluster straddles an edge**. When the window cuts through the middle of a double-width glyph, that glyph is excluded from the byte range and the visible half-column is reported as padding, so your columns still line up.

```crystal
sl = UW.slice_cols("a\u65E5\u672Cb", 1, 4)   # columns [1, 4)
# 日 occupies cols 1–2, 本 cols 3–4; window [1,4) shows 日 fully and half of 本
# sl.offset / sl.size        → bytes of 日
# sl.pad_left  == 0
# sl.pad_right == 1          → 本 was bisected; one pad column stands in for it
```

Edge cases: an empty or inverted range (`end_col <= start_col`) returns a zero-length slice with both pads `0` and the bounds echoed. A range entirely past the end of the string returns a zero-length slice — the loop simply finds no cells in range. A negative `start_col` is clamped to `0`.

**`pad_left` and `pad_right` only ever count a bisected wide glyph.** They are *not* the fill for a short line. When the window extends past the end of the content, no glyph straddles the right edge, so `pad_right` stays `0` and the returned columns cover only the real text — it is the caller's job to pad the remainder out to the window width. This is the single most important thing to get right, and it drives the example below.

#### Worked example: render one scrolled, clipped row

Take a line, a horizontal scroll offset, and a viewport width, and produce exactly the cells to draw, padded to the full width. Note the third argument is `scroll + width`, an **absolute** end column, not the width.

To pad correctly you need the column width of the middle segment. Measure the emitted bytes with `swidth` — it is right in every case, including a line shorter than the window, because it counts only the real characters and lets the trailing pad cover the rest.

```crystal
def render_row(io : IO, line : String, scroll : Int32, width : Int32) : Nil
  sl = UW.slice_cols(line, scroll, scroll + width)

  filled = 0
  filled += emit_spaces(io, sl.pad_left)

  if sl.size > 0
    text = line.byte_slice(sl.offset, sl.size)
    io << text
    filled += UW.swidth(text)
  end

  filled += emit_spaces(io, sl.pad_right)
  emit_spaces(io, width - filled)   # pad short lines out to the full width
end

def emit_spaces(io : IO, n : Int32) : Int32
  return 0 if n <= 0
  n.times { io << ' ' }
  n
end
```

> **Optimization — only when the window is fully covered.** If you can *guarantee* the content spans the whole window (e.g. a wide document scrolled well within its bounds, never past the last column), you can skip the `swidth` pass and derive the segment width from the slice: it is the window span minus the two pads.
>
> ```crystal
> seg    = (sl.end_col - sl.start_col) - sl.pad_left - sl.pad_right
> filled = sl.pad_left + seg + sl.pad_right   # == end_col - start_col
> ```
>
> This is wrong the moment the window runs past the end of a short line: `pad_right` is `0` there (nothing straddled the edge), so `seg` is computed as the full remaining window while only the real characters were emitted, and the line is left under-filled. `slice_cols` gives you no flag distinguishing "covered" from "past the end," so use this form only where coverage is an invariant you already hold, never as the default.

## Placing a cursor by column

`offset_to_col` and `col_to_offset` convert between byte offsets and display columns; `next_grapheme` / `prev_grapheme` move a byte offset by whole clusters.

```crystal
s = "a\u4E00b\u4E01c"                # a 一 b 丁 c  →  columns a=0 一=1 b=3 丁=4 c=6
UW.offset_to_col(s, 4)              # => 3   byte 4 (the 'b') sits at column 3
UW.col_to_offset(s, 3)             # => 4   column 3 maps back to byte 4

UW.next_grapheme(s, 1)             # => 4   past 一 (3 bytes)
UW.prev_grapheme(s, 4)             # => 1
```

Edge cases: `offset_to_col` clamps a non-positive offset to column `0`; an offset past the end returns the string's full width. `col_to_offset` clamps a non-positive column to offset `0`; a column past the end returns the end offset, and a column landing *inside* a wide cluster returns that cluster's start offset (it never points into the middle of a glyph). `next_grapheme` at or past the end returns the end; `prev_grapheme` at or before `0` returns `0`.

Column math honors `WidthOpts`, so legacy mode, a custom cap, and ambiguous promotion all carry through.

## Walking clusters

`clusters` yields a `Span` per grapheme cluster with `width`, `size`, and `kind`.

```crystal
UW.clusters("a\u0301\u65E5\u{1F468}\u200D\u{1F469}").each do |span|
  span.width   # display columns
  span.size    # code units consumed
  span.kind    # SpanKind
end

UW.grapheme_next("e\u0301x")   # => 3   size of the first cluster ('e' + U+0301)
```

`SpanKind` classifies the cluster for a renderer that treats whitespace and controls specially:

- `Graphemic` — ordinary printable cluster.
- `Tab` — U+0009.
- `CR` — a lone carriage return; `LF` — a line feed **and** the other vertical whitespace folded to it: U+000B, U+000C, U+0085, U+2028, U+2029; `CRLF` — a CR+LF pair returned as one span.
- `Control` — any other control character.

Segmentation passes `GraphemeBreakTest.txt` 17.0.0, including Indic conjuncts (GB9c), emoji ZWJ (GB11), and regional-indicator pairing (GB12/13). For the raw one-codepoint-at-a-time decision, drive `UW::State#grapheme_break` yourself.

## Finding wrap points

`line_breaks` yields UAX #14 break opportunities; each `BreakSpan` covers the segment ending at that opportunity.

```crystal
UW.line_breaks("The quick-brown fox").each do |brk|
  brk.width      # columns in this segment
  brk.size       # code units
  brk.mandatory  # true only at a hard newline or end of text
end

UW.line_break_next("ab cd")   # => 3   size of the first segment ("ab ")
```

It reports *where* a line may break — numeric sequences, quotation, Korean jamo, Brahmic viramas are all resolved — and passes `LineBreakTest.txt`. Actually laying out wrapped lines against a width is the caller's job; combine it with `swidth` or `truncate`. `line_breaks("")` yields nothing.

## Width models (legacy vs. mode 2027)

`WidthOpts` selects how clusters are measured. `WidthMode::Unicode` is grapheme-aware: it promotes a narrow emoji base under VS16 and coalesces ZWJ sequences. `WidthMode::Legacy` sums code points independently, matching a terminal that hasn't adopted mode 2027.

```crystal
UW.swidth("\u2764\uFE0F", opts: UW::WidthOpts.unicode)  # => 2
UW.swidth("\u2764\uFE0F", opts: UW::WidthOpts.legacy)   # => 1
```

Build variants fluently; each setter returns a new value:

```crystal
UW::WidthOpts.unicode
  .with_mode(UW::WidthMode::Legacy)
  .with_cap(0)                        # disable the cluster cap
  .with_ambiguous_wide(true)          # promote ambiguous-width chars
```

### Resolving the model from the terminal

`Config` turns a terminal's declared mode-2027 state into a `WidthMode`, falling back to legacy when unsupported or reset. `opts` takes an optional cap.

```crystal
cfg = UW::Config.new(supported: true, state: UW::Mode2027State::Set)
cfg.width_mode           # => WidthMode::Unicode
cfg.grapheme_processing? # => true
UW.swidth(text, opts: cfg.opts)       # default cap
UW.swidth(text, opts: cfg.opts(4))    # cap at 4
```

### Ambiguous-width characters

East Asian ambiguous characters are narrow by default; `ambiguous_wide` promotes them. It is the one setting `width_cp`'s options form exists to honor.

```crystal
wide = UW::WidthOpts.unicode.with_ambiguous_wide(true)
UW.swidth("\u00A7\u00B1\u2103")             # => 3
UW.swidth("\u00A7\u00B1\u2103", opts: wide) # => 6
UW.width_cp(0x00A7_u32, wide)               # => 2
```

## Encodings

Every entry point is overloaded for `String`, `Bytes`, and `Slice(UInt32)`, and the behavior is identical across them — only the unit of `size`/offset changes. The UTF-8 paths take a `Utf8Policy` positionally after the buffer; the UTF-32 path skips decoding entirely.

```crystal
UW.swidth(str)                              # String
UW.swidth(bytes, UW::Utf8Policy::Strict)    # Bytes, strict
UW.swidth(slice_of_u32)                     # UTF-32

UW.cells(bytes, UW::Utf8Policy::Strict)
UW.next_grapheme(bytes, off, UW::Utf8Policy::Strict)
```

## Performance

Allocation-free on the hot path. Iterators are stack-allocated structs with `reset`, so one iterator can be reused across many buffers without reallocating — the pattern to use when measuring a screen's worth of lines per frame.

```crystal
it = UW.clusters("ab".to_slice)
it.each { |span| ... }
it.reset("\u4E00\u4E01".to_slice)   # same struct, new buffer
it.each { |span| ... }
```

Every iterator supports it: `Utf32Clusters`, `Utf8Clusters`, `Utf32LineBreaks`, `Utf8LineBreaks`, `Utf32Cells`, `Utf8Cells`. Run `make bench` for figures on your hardware.

## API summary

| Function                          | Purpose                                                        |
|-----------------------------------|----------------------------------------------------------------|
| `swidth`                          | Total display width of a string                                |
| `width`                           | Width and size of the first grapheme cluster                   |
| `width_cp`                        | Width of a single scalar (mode / opts overloads)               |
| `truncate`                        | Largest cluster-safe prefix within a column budget             |
| `slice_cols`                      | Byte range for a column window, with edge padding (`ColSlice`) |
| `cells`                           | Iterator over clusters with column positions (`Cell`)          |
| `offset_to_col` / `col_to_offset` | Map between byte offsets and columns                           |
| `next_grapheme` / `prev_grapheme` | Cluster boundary navigation                                    |
| `clusters`                        | Iterator over grapheme clusters (`Span`)                       |
| `grapheme_next`                   | Size of the next grapheme cluster                              |
| `line_breaks`                     | Iterator over line-break opportunities (`BreakSpan`)           |
| `line_break_next`                 | Size of the first line segment                                 |
| `unicode_version`                 | The UCD version the tables were built from                     |

Option and policy types: `WidthOpts`, `WidthMode`, `Config`, `Mode2027State`, `CtrlPolicy`, `Utf8Policy`, `SpanKind`, `State`.

Record types you destructure: `Span`, `BreakSpan`, `Cell`, `ColSlice`.

## License

MIT.