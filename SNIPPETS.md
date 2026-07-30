SNIPPETS: uw-cr
===============

### single codepoint width

```cr
require "uw-cr"

# returns : Int32  (-1 for control, 0/1/2 for printable)
w = UW.width_cp(0x1F600_u32)
```

### first-cluster width from a codepoint slice

```cr
require "uw-cr"

# returns : {Int32, Int32}  =>  {display_width, codepoints_consumed}
cps = Slice[0x0065_u32, 0x0301_u32]
width, consumed = UW.width(cps)
```

### first-cluster width from UTF-8 bytes

```cr
require "uw-cr"

# policy  : UW::Utf8Policy  =>  Replace (default) | Strict
# returns : {Int32, Int32}  =>  {display_width, bytes_consumed}
width, consumed = UW.width("é".to_slice)
width, consumed = UW.width("é".to_slice, UW::Utf8Policy::Strict)
```

### first-cluster width from a String

```cr
require "uw-cr"

# policy  : UW::Utf8Policy  =>  Replace (default) | Strict
# returns : {Int32, Int32}  =>  {display_width, bytes_consumed}
width, consumed = UW.width("👨‍👩‍👧")
width, consumed = UW.width("👨‍👩‍👧", UW::Utf8Policy::Strict)
```

### advance one grapheme cluster (codepoint slice)

```cr
require "uw-cr"

# returns : Int32  =>  codepoints in the next cluster
cps = Slice[0x0065_u32, 0x0301_u32]
n = UW.grapheme_next(cps)
```

### advance one grapheme cluster (UTF-8 bytes)

```cr
require "uw-cr"

# policy  : UW::Utf8Policy  =>  Replace (default) | Strict
# returns : Int32  =>  bytes in the next cluster
n = UW.grapheme_next("é".to_slice)
n = UW.grapheme_next("é".to_slice, UW::Utf8Policy::Strict)
```

### advance one grapheme cluster (String)

```cr
require "uw-cr"

# policy  : UW::Utf8Policy  =>  Replace (default) | Strict
# returns : Int32  =>  bytes in the next cluster
n = UW.grapheme_next("héllo")
n = UW.grapheme_next("héllo", UW::Utf8Policy::Strict)
```

### total string width (codepoint slice)

```cr
require "uw-cr"

# ctrl    : UW::CtrlPolicy  =>  Skip (default) | Fail
# returns : Int32  =>  summed width, or -1 if ctrl==Fail hits a control
cps = Slice[0x0065_u32, 0x0301_u32]
total = UW.swidth(cps)
total = UW.swidth(cps, UW::CtrlPolicy::Fail)
```

### total string width (UTF-8 bytes)

```cr
require "uw-cr"

# upolicy : UW::Utf8Policy  =>  Replace (default) | Strict
# ctrl    : UW::CtrlPolicy  =>  Skip (default) | Fail
# returns : Int32  =>  summed width, or -1 if ctrl==Fail hits a control
# note    : ctrl is the third positional param; pass upolicy to reach it
total = UW.swidth("hello".to_slice)
total = UW.swidth("hello".to_slice, UW::Utf8Policy::Replace, UW::CtrlPolicy::Fail)
```

### total string width (String)

```cr
require "uw-cr"

# upolicy : UW::Utf8Policy  =>  Replace (default) | Strict
# ctrl    : UW::CtrlPolicy  =>  Skip (default) | Fail
# returns : Int32  =>  summed width, or -1 if ctrl==Fail hits a control
# note    : ctrl is the third positional param; pass upolicy to reach it
total = UW.swidth("caña 🇯🇵")
total = UW.swidth("caña 🇯🇵", UW::Utf8Policy::Replace, UW::CtrlPolicy::Fail)
```

### the Unicode version backing the tables

```cr
require "uw-cr"

# returns : String
ver = UW.unicode_version
```

### the shard version

```cr
require "uw-cr"

# returns : String
lib_ver = UW::VERSION
```

### iterate every grapheme cluster in a String

```cr
require "uw-cr"

# with the default Replace policy, malformed bytes consume 1 (U+FFFD),
# so len is always >= 1 and the loop terminates
s = "a👨‍👩‍👧b🇯🇵c"
bytes = s.to_slice
off = 0
while off < bytes.size
  w, len = UW.width(bytes + off)
  # w   : Int32  =>  cluster display width
  # len : Int32  =>  cluster byte length
  off += len
end
```

### iterate every grapheme cluster under Strict policy

```cr
require "uw-cr"

# Strict stops at the first malformed byte, returning len == 0;
# guard against it to avoid an infinite loop
s = "a👨‍👩‍👧b🇯🇵c"
bytes = s.to_slice
off = 0
while off < bytes.size
  w, len = UW.width(bytes + off, UW::Utf8Policy::Strict)
  break if len == 0
  off += len
end
```

### policy enums

```cr
require "uw-cr"

# UW::Utf8Policy  =>  Replace (malformed => U+FFFD) | Strict (stop at malformed)
# UW::CtrlPolicy  =>  Skip (ignore controls) | Fail (return -1 on control)
```