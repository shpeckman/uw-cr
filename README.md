# uw-cr

Unicode text measurement and segmentation for Crystal (UCD 17.0.0): display width, grapheme clusters (UAX #29), line breaks (UAX #14).  
Backed by a two-stage property trie generated from the UCD.  

Works on `String`, `Bytes` (UTF-8), and `Slice(UInt32)` (UTF-32).  
No hot-path allocation.  

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

## Quick start

```crystal
require "uw-cr"

UW.swidth("日本語 café 👨‍👩‍👧")   # => 14
UW.width_cp(0x4E00)                # => 2

UW.clusters("a̐é👨‍👩‍👧").each do |span|
  span.width   # display columns
  span.size    # code units consumed (bytes for UTF-8)
  span.kind    # SpanKind::Graphemic, Control, CR, LF, CRLF, Tab
end

UW.line_breaks("well-known café").each do |brk|
  brk.width      # columns in this segment
  brk.size       # code units
  brk.mandatory  # true at a hard break or end of text
end
```

## Measuring width

`swidth` totals a string.  
`width_cp` measures one scalar.  
`width` measures the first grapheme cluster and reports the code units it spanned.  

```crystal
UW.swidth("hello")                 # => 5
UW.swidth("\u2764\uFE0F")          # => 2   heart + VS16 → emoji presentation
UW.width_cp('A'.ord.to_u32)        # => 1
UW.width_cp(0x1B_u32)              # => -1  control
w, consumed = UW.width("éx")       # => {1, 2}
```

Widths follow the terminal convention: `0` for combining marks and zero-width formatting, `1` narrow, `2` wide (CJK, emoji presentation), `-1` control.  

`width_cp` has three forms: the bare scalar above, a mode override (`width_cp(cp, UW::WidthMode::Legacy)`), and an options form (`width_cp(cp, opts)`) — the last is the only one that honours `ambiguous_wide`.  

```crystal
UW.width_cp(0x00A7_u32)                                              # => 1
UW.width_cp(0x00A7_u32, UW::WidthOpts.unicode.with_ambiguous_wide(true)) # => 2
```

### Control handling

`CtrlPolicy` decides what `swidth` does with a control character: `Skip` (default) omits it, `Fail` collapses the total to `-1`.  
On the UTF-32 path it is the first positional argument; on `String` / `Bytes` it follows `Utf8Policy`, so pass it by name.  

```crystal
UW.swidth(cps, UW::CtrlPolicy::Fail)         # UTF-32: positional
UW.swidth(str, ctrl: UW::CtrlPolicy::Fail)   # String/Bytes: named
```

### Cluster width cap

A cluster is capped at `CLUSTER_WIDTH_CAP` (2) columns, matching how terminals render an unbounded ZWJ sequence as one double-wide cell.  
A cap of `0` disables it and sums the true per-codepoint width.  

```crystal
family = "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}"
UW.swidth(family)                                           # => 2   capped
UW.swidth(family, opts: UW::WidthOpts.unicode.with_cap(0))  # => 8   uncapped
```

## Width modes and mode 2027

`WidthOpts` picks a width model.  
`WidthMode::Unicode` is grapheme-aware: VS16 presentation promotion, ZWJ coalescing.  
`WidthMode::Legacy` sums code points independently.  

```crystal
UW.swidth("\u2764\uFE0F", opts: UW::WidthOpts.unicode)  # => 2
UW.swidth("\u2764\uFE0F", opts: UW::WidthOpts.legacy)   # => 1
```

Build variants from a base with the fluent setters; each returns a new `WidthOpts`.  

```crystal
UW::WidthOpts.unicode
  .with_mode(UW::WidthMode::Legacy)   # switch width model
  .with_cap(0)                        # disable the cluster cap
  .with_ambiguous_wide(true)          # promote ambiguous-width chars
```

`Config` resolves a `WidthMode` from a terminal's declared mode-2027 state, falling back to legacy when unsupported or reset.  

```crystal
cfg = UW::Config.new(supported: true, state: UW::Mode2027State::Set)
cfg.width_mode           # => WidthMode::Unicode
cfg.grapheme_processing? # => true
UW.swidth(text, opts: cfg.opts)
```

### Ambiguous-width characters

East Asian ambiguous characters are narrow by default; `ambiguous_wide` promotes them.  

```crystal
wide = UW::WidthOpts.unicode.with_ambiguous_wide(true)
UW.swidth("§±℃")             # => 3
UW.swidth("§±℃", opts: wide) # => 6
UW.width_cp(0x00A7_u32, wide) # => 2   the options form of width_cp
```

## Grapheme segmentation

`clusters` yields `Span` values with width, size, and kind.  
`grapheme_next` returns the size of the next cluster.  
`State` exposes the raw UAX #29 break decision one code point at a time.  

```crystal
UW.clusters(text).each { |span| ... }
UW.grapheme_next("e\u0301x")   # => 3   'e' + U+0301

st = UW::State.new
cps.each { |cp| new_cluster = st.grapheme_break(cp) }
```

`Span` carries `width`, `size`, and `kind` (a `SpanKind`).  
`size` and `grapheme_next` count code units: bytes on UTF-8, `UInt32` elements on UTF-32.  
Segmentation passes `GraphemeBreakTest.txt` 17.0.0, including Indic conjuncts (GB9c), emoji ZWJ (GB11), and regional-indicator pairing (GB12/13).  

## Line breaking

`line_breaks` yields UAX #14 break opportunities.  
Each `BreakSpan` gives the `width` and `size` of the segment ending there, and whether the break is `mandatory` (a hard newline, or end of text).  

```crystal
UW.line_breaks("The quick-brown fox").each do |brk|
  brk.mandatory  # false at soft opportunities, true at newlines / EOT
end

UW.line_break_next("ab cd")                          # => 3   String
UW.line_break_next(bytes, UW::Utf8Policy::Strict)    # Bytes
UW.line_break_next(cps)                              # UTF-32
```

It resolves the full rule set — numeric sequences, quotation, Korean jamo, Brahmic viramas — and passes `LineBreakTest.txt`.  
It reports where lines may break; wrapping is the caller's.  

## Column mapping

The `cells` family maps between byte offsets and display columns for cursor positioning and slicing.  
Each `Cell` carries `offset`, `size`, `width`, `col`, and `kind` (a `SpanKind`).  

```crystal
UW.cells(text).each do |cell|
  cell.offset  # byte offset
  cell.size    # code units
  cell.col     # starting column
  cell.width   # display width
  cell.kind    # SpanKind
end

UW.offset_to_col(text, offset)
UW.col_to_offset(text, col)
UW.next_grapheme(text, offset)
UW.prev_grapheme(text, offset)
```

Every function here honours `WidthOpts`, so column math respects legacy mode, a custom cap, and ambiguous promotion — and the `String` / `Bytes` overloads take a `Utf8Policy`.  

```crystal
wide = UW::WidthOpts.unicode.with_ambiguous_wide(true)
UW.offset_to_col(text, offset, opts: wide)
UW.col_to_offset(bytes, col, UW::Utf8Policy::Strict, wide)
```

`slice_cols` returns a `ColSlice` for a half-open column span.  
Alongside the byte range (`offset` / `size`) it echoes the resolved bounds (`start_col` / `end_col`) and the padding needed when a wide cluster straddles either edge (`pad_left` / `pad_right`).  
It also accepts `opts:` and a `Utf8Policy`.  

```crystal
sl = UW.slice_cols("a日本b", 1, 4)
# sl.offset / sl.size        → byte range inside [1, 4)
# sl.start_col / sl.end_col  → resolved column bounds
# sl.pad_left / sl.pad_right → fill where a wide cluster was clipped
```

## Truncation

`truncate` returns the largest prefix within a column budget without splitting a cluster, as width consumed and cut offset.  
It accepts a `Utf8Policy` and `WidthOpts` like the other measurement entry points.  

```crystal
width, offset = UW.truncate("日本語 is fun", 6)
# => {6, 9}

wide = UW::WidthOpts.unicode.with_ambiguous_wide(true)
UW.truncate("a§b", 2, opts: wide)   # promoted § counts as 2
```

## Encodings

Every entry point is overloaded for `String`, `Bytes`, and `Slice(UInt32)`.  
The UTF-8 paths take a `Utf8Policy`: `Replace` (default) advances one byte on bad input as U+FFFD; `Strict` stops at the first invalid byte.  
This applies throughout — width, segmentation, line breaks, column mapping, navigation, and truncation — not just `swidth`.  
The UTF-32 paths skip decoding.  

```crystal
UW.swidth(str)                              # String
UW.swidth(bytes, UW::Utf8Policy::Strict)    # Bytes, strict
UW.swidth(slice_of_u32)                     # UTF-32

UW.cells(bytes, UW::Utf8Policy::Strict)             # policy on cells
UW.next_grapheme(bytes, off, UW::Utf8Policy::Strict) # …and navigation
```

## Performance

Allocation-free on the hot path; iterators are stack-allocated structs with `reset` for reuse across buffers without reallocating.  
Every iterator — `Utf32Clusters`, `Utf8Clusters`, `Utf32LineBreaks`, `Utf8LineBreaks`, `Utf32Cells`, `Utf8Cells` — supports it.  

```crystal
it = UW.clusters("ab".to_slice)
it.each { |span| ... }
it.reset("\u4E00\u4E01".to_slice)   # same struct, new buffer
it.each { |span| ... }
```

Run `make bench` for figures on your hardware.

## API summary

| Function                          | Purpose                                                      |
|-----------------------------------|--------------------------------------------------------------|
| `swidth`                          | Total display width of a string                              |
| `width`                           | Width and size of the first grapheme cluster                 |
| `width_cp`                        | Width of a single scalar (mode / opts overloads)             |
| `clusters`                        | Iterator over grapheme clusters (`Span`)                     |
| `grapheme_next`                   | Size of the next grapheme cluster                            |
| `line_breaks`                     | Iterator over line-break opportunities (`BreakSpan`)         |
| `line_break_next`                 | Size of the first line segment                               |
| `truncate`                        | Largest cluster-safe prefix within a column budget           |
| `cells`                           | Iterator over clusters with column positions (`Cell`)        |
| `offset_to_col` / `col_to_offset` | Map between byte offsets and columns                         |
| `next_grapheme` / `prev_grapheme` | Cluster boundary navigation                                  |
| `slice_cols`                      | Byte range for a column span, with edge padding (`ColSlice`) |
| `unicode_version`                 | The UCD version the tables were built from                   |

Option and policy types: 
- `WidthOpts`
- `WidthMode`
- `Config`
- `Mode2027State`
- `CtrlPolicy`
- `Utf8Policy`
- `SpanKind`
- `State`

Record types you destructure: 
- `Span`
- `BreakSpan`
- `Cell`
- `ColSlice`

## License

MIT.