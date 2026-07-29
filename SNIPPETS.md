SNIPPETS: uw-cr
===============

### usage-stub

```cr
require "uw-cr"

# ── single codepoint width ─────────────────────────────────────
# returns : Int32  (-1 for control, 0/1/2 for printable)
w = UW.width_cp(0x1F600_u32)

# ── first-cluster width from a codepoint slice ─────────────────
# returns : {Int32, Int32}  =>  {display_width, codepoints_consumed}
cps = Slice[0x0065_u32, 0x0301_u32]
width, consumed = UW.width(cps)

# ── first-cluster width from UTF-8 bytes ───────────────────────
# policy  : UW::Utf8Policy  =>  Replace (default) | Strict
# returns : {Int32, Int32}  =>  {display_width, bytes_consumed}
width, consumed = UW.width("é".to_slice)
width, consumed = UW.width("é".to_slice, UW::Utf8Policy::Strict)

# ── first-cluster width from a String ──────────────────────────
# policy  : UW::Utf8Policy  =>  Replace (default) | Strict
# returns : {Int32, Int32}  =>  {display_width, bytes_consumed}
width, consumed = UW.width("👨‍👩‍👧")
width, consumed = UW.width("👨‍👩‍👧", UW::Utf8Policy::Strict)

# ── advance one grapheme cluster (codepoint slice) ─────────────
# returns : Int32  =>  codepoints in the next cluster
n = UW.grapheme_next(cps)

# ── advance one grapheme cluster (UTF-8 bytes) ─────────────────
# policy  : UW::Utf8Policy  =>  Replace (default) | Strict
# returns : Int32  =>  bytes in the next cluster
n = UW.grapheme_next("é".to_slice)
n = UW.grapheme_next("é".to_slice, UW::Utf8Policy::Strict)

# ── advance one grapheme cluster (String) ──────────────────────
# policy  : UW::Utf8Policy  =>  Replace (default) | Strict
# returns : Int32  =>  bytes in the next cluster
n = UW.grapheme_next("héllo")
n = UW.grapheme_next("héllo", UW::Utf8Policy::Strict)

# ── total string width (codepoint slice) ───────────────────────
# ctrl    : UW::CtrlPolicy  =>  Skip (default) | Fail
# returns : Int32  =>  summed width, or -1 if ctrl==Fail hits a control
total = UW.swidth(cps)
total = UW.swidth(cps, UW::CtrlPolicy::Fail)

# ── total string width (UTF-8 bytes) ───────────────────────────
# upolicy : UW::Utf8Policy  =>  Replace (default) | Strict
# ctrl    : UW::CtrlPolicy  =>  Skip (default) | Fail
# returns : Int32  =>  summed width, or -1 if ctrl==Fail hits a control
total = UW.swidth("hello".to_slice)
total = UW.swidth("hello".to_slice, UW::Utf8Policy::Strict, UW::CtrlPolicy::Fail)

# ── total string width (String) ────────────────────────────────
# upolicy : UW::Utf8Policy  =>  Replace (default) | Strict
# ctrl    : UW::CtrlPolicy  =>  Skip (default) | Fail
# returns : Int32  =>  summed width, or -1 if ctrl==Fail hits a control
total = UW.swidth("caña 🇯🇵")
total = UW.swidth("caña 🇯🇵", UW::Utf8Policy::Strict, UW::CtrlPolicy::Fail)

# ── the Unicode version backing the tables ─────────────────────
# returns : String
ver = UW.unicode_version

# ── the shard version ──────────────────────────────────────────
# returns : String
lib_ver = UW::VERSION

# ── iterate every grapheme cluster in a String ─────────────────
s = "a👨‍👩‍👧b🇯🇵c"
bytes = s.to_slice
off = 0
while off < bytes.size
  w, len = UW.width(bytes + off)
  # w   : Int32  =>  cluster display width
  # len : Int32  =>  cluster byte length
  off += len
end

# ── policy enums ───────────────────────────────────────────────
# UW::Utf8Policy  =>  Replace (malformed => U+FFFD) | Strict (stop at malformed)
# UW::CtrlPolicy  =>  Skip (ignore controls) | Fail (return -1 on control)
```