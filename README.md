# uw-cr

Unicode text measurement and segmentation for Crystal, conformant to UCD 17.0.0.

`uw-cr` answers two questions about text: how wide is it when rendered in a
monospaced terminal, and where are its boundaries. It implements display-width
calculation, grapheme cluster segmentation (UAX #29), and line-break opportunity
detection (UAX #14), all backed by a packed two-stage property trie generated
directly from the Unicode Character Database.

The library operates on `String`, `Bytes` (UTF-8), and `Slice(UInt32)` (UTF-32)
without allocating on the hot path.

## Installation

Add the dependency to `shard.yml`:

```yaml
dependencies:
  uw-cr:
    github: shpeckman/uw-cr
```

Then generate the property tables, which downloads the UCD 17.0.0 data files and
writes the packed binary blobs the library reads at compile time:

```
make setup
```

Run `make spec` to verify against the official `GraphemeBreakTest.txt` and
`LineBreakTest.txt` conformance suites. The spec suite downloads those two files
itself on first run and caches them under your system cache directory
(`$XDG_CACHE_HOME/uw-cr/<version>`, falling back to `~/.cache`), keyed by the UCD
version the tables were built from, so no separate setup step is needed for them.

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
  brk.mandatory  # true at a hard break (newline) or end of text
end
```

## Measuring width

`swidth` returns the total display width of a whole string. `width_cp` returns
the width of a single scalar. `width` measures only the first grapheme cluster
and reports how many code units it spanned, which is the primitive the iterators
are built on.

```crystal
UW.swidth("hello")                 # => 5
UW.swidth("\u2764\uFE0F")          # => 2   (heart + VS16 → emoji presentation)
UW.width_cp('A'.ord.to_u32)        # => 1
UW.width_cp(0x1B_u32)              # => -1  (control)
w, consumed = UW.width("éx")       # => {1, 2}
```

Width values follow the terminal convention: `0` for combining marks and
zero-width formatting, `1` for narrow, `2` for wide (CJK, emoji presentation),
and `-1` for control characters.

### Control handling

`swidth` takes a `CtrlPolicy` deciding what happens when a control character is
encountered. `Skip` (the default) omits it from the total; `Fail` collapses the
whole measurement to `-1`. On the UTF-32 path `CtrlPolicy` is the first optional
argument; on the `String` / `Bytes` paths it follows the `Utf8Policy`, so pass it
by name.

```crystal
UW.swidth(cps, UW::CtrlPolicy::Fail)         # UTF-32: positional
UW.swidth(str, ctrl: UW::CtrlPolicy::Fail)   # String/Bytes: named
```

### Cluster width cap

A single grapheme cluster is capped at `CLUSTER_WIDTH_CAP` (2) columns by
default, matching how terminals render an unbounded ZWJ emoji sequence as one
double-wide cell. Override the cap through `WidthOpts`; a cap of `0` disables
capping and sums the true per-codepoint width.

```crystal
family = "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}"
UW.swidth(family)                                       # => 2  (capped)
UW.swidth(family, opts: UW::WidthOpts.unicode.with_cap(0))  # => 8  (uncapped)
```

## Width modes and mode 2027

`WidthOpts` selects between two width models. `WidthMode::Unicode` applies modern
grapheme-aware rules, including emoji-presentation promotion under VS16 and ZWJ
coalescing. `WidthMode::Legacy` sums code points independently, matching
pre-grapheme terminal behaviour.

```crystal
UW.swidth("\u2764\uFE0F", opts: UW::WidthOpts.unicode)  # => 2
UW.swidth("\u2764\uFE0F", opts: UW::WidthOpts.legacy)   # => 1
```

`Config` models terminal support for mode 2027 (the proposal for grapheme-cluster
width) and resolves the appropriate `WidthMode` from the terminal's declared
state, so callers can drive width behaviour from what the terminal actually
advertises rather than hard-coding a mode.

```crystal
cfg = UW::Config.new(supported: true, state: UW::Mode2027State::Set)
cfg.width_mode          # => WidthMode::Unicode
cfg.grapheme_processing? # => true
UW.swidth(text, opts: cfg.opts)
```

When mode 2027 is unsupported or reset, `Config` falls back to legacy width.

### Ambiguous-width characters

East Asian ambiguous characters render as either width depending on context.
They are treated as narrow by default; enable `ambiguous_wide` to promote them.

```crystal
wide = UW::WidthOpts.unicode.with_ambiguous_wide(true)
UW.swidth("§±℃")            # => 3
UW.swidth("§±℃", opts: wide) # => 6
```

## Grapheme segmentation

`clusters` returns an iterator over grapheme clusters, each reported as a `Span`
carrying its display width, code-unit size, and kind. `grapheme_next` returns
just the size of the next cluster, and the low-level `State` struct exposes the
UAX #29 break decision one code point at a time for callers that manage their own
buffer.

```crystal
UW.clusters(text).each { |span| ... }
UW.grapheme_next("e\u0301x")   # => 3  (bytes: 'e' + U+0301 combining mark)

st = UW::State.new
cps.each { |cp| new_cluster = st.grapheme_break(cp) }
```

Like `size` on a `Span`, `grapheme_next` counts code units: bytes on the UTF-8
(`String` / `Bytes`) paths, and `UInt32` elements on the UTF-32 path.

The implementation passes every case in the Unicode 17.0.0
`GraphemeBreakTest.txt`, including Indic conjunct breaks (GB9c), emoji ZWJ
sequences (GB11), and regional-indicator pairing (GB12/13).

## Line breaking

`line_breaks` returns an iterator over line-break opportunities per UAX #14. Each
`BreakSpan` reports the width and size of the segment ending at that opportunity,
and whether the break is mandatory (a hard newline, or end of text).

```crystal
UW.line_breaks("The quick-brown fox").each do |brk|
  brk.mandatory  # false at soft opportunities, true at newlines / EOT
end

UW.line_break_next("ab cd")   # => 3  (size of the first segment)
```

The line-breaker resolves the full UAX #14 rule set, including numeric sequences,
quotation handling, Korean jamo, and Brahmic viramas, and passes the official
`LineBreakTest.txt` conformance suite (10,000+ cases). Note that this reports
*where lines may break*; it does not perform wrapping, which is a layout policy
left to the caller.

## Column mapping

For cursor positioning and horizontal slicing in a terminal grid, the `cells`
family maps between byte offsets and display columns.

```crystal
UW.cells(text).each do |cell|
  cell.offset  # byte offset of this cluster
  cell.col     # starting column
  cell.width   # display width
end

UW.offset_to_col(text, offset)   # column at a byte offset
UW.col_to_offset(text, col)      # byte offset at a column
UW.next_grapheme(text, offset)   # offset of the following cluster boundary
UW.prev_grapheme(text, offset)   # offset of the preceding cluster boundary
```

`slice_cols` extracts the byte range covering a half-open column span and reports
how many padding cells are needed when a wide cluster straddles either edge, so a
double-wide character clipped at the boundary can be replaced with spaces.

```crystal
sl = UW.slice_cols("a日本b", 1, 4)
# sl.offset / sl.size    → the byte range fully inside [1, 4)
# sl.pad_left / pad_right → cells to fill where a wide cluster was clipped
```

## Truncation

`truncate` finds the largest prefix fitting within a column budget without ever
splitting a cluster across the boundary. It returns the width consumed and the
byte offset of the cut point.

```crystal
width, offset = UW.truncate("日本語 is fun", 6)
# => {6, 9}   → "日本語" fits in 6 columns, ending at byte 9
```

## Encodings

Every entry point is overloaded for `String`, `Bytes`, and `Slice(UInt32)`.
The UTF-8 paths (`String` / `Bytes`) take a `Utf8Policy` governing malformed
input: `Replace` (the default) advances one byte and treats the bad sequence as
U+FFFD, while `Strict` stops at the first invalid byte.

```crystal
UW.swidth(str)                              # String
UW.swidth(bytes, UW::Utf8Policy::Strict)    # Bytes, strict decoding
UW.swidth(slice_of_u32)                     # UTF-32, no decode step
```

The UTF-32 paths skip UTF-8 decoding entirely and are the fastest option when
input is already decoded.

## Performance

Measurement and segmentation are allocation-free on the hot path — the iterators
are stack-allocated structs with `reset` methods for reuse across buffers, so
tight loops never touch the heap. Scalar width lookup is a two-stage trie read
sustaining several GiB/s; grapheme segmentation runs several times faster than
the standard library's `String#grapheme_size` on the same UTF-8 input. Run
`make bench` to reproduce the figures on your own hardware.

## API summary

| Function                          | Purpose                                                      |
|-----------------------------------|--------------------------------------------------------------|
| `swidth`                          | Total display width of a string                              |
| `width`                           | Width and size of the first grapheme cluster                 |
| `width_cp`                        | Width of a single scalar                                     |
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

Supporting types: `WidthOpts`, `WidthMode`, `Config`, `Mode2027State`,
`CtrlPolicy`, `Utf8Policy`, `SpanKind`, and the `State` segmentation primitive.

## License

MIT.
