# uw.cr

Crystal bindings for the header-only `uw` Unicode width + grapheme
segmentation C library (Unicode 17.0.0).

## Event loop

`uw` is a pure CPU library: every function is synchronous, non-blocking,
reentrant, and thread-safe, with read-only tables and no mutated globals.
Nothing here touches a file descriptor or blocks, so there is nothing to
register with Crystal's event loop, and no fiber is ever parked by a call.
The bindings pass buffers by pointer + length (zero copy), keep the C
`uw_state` / `uw_cluster` as stack `struct`s, and are safe to call from any
fiber or thread. That is the whole of "playing along with the event loop"
for a library of this shape.

## Layout

    src/uw/uw.h        the vendored header-only library
    src/uw/uw_impl.c   one TU that instantiates UW_IMPLEMENTATION
    Makefile           builds a static ext/libuw.a
    src/uw/lib_uw.cr   low-level lib binding
    src/uw.cr          high-level idiomatic API
    spec/uw_spec.cr    tests

## Cluster-width cap

The cap (`2` default, `0` for kitty-style no-cap) is a compile-time constant
of the C build; Crystal cannot change it afterward. Build with the cap you
need and read it back at runtime via `Uw.active_width_cap` so callers stay in
sync with the compiled library.

    make            # cap 2 (default)
    make UW_CAP=0   # no cap

## Build / link — approach A: shard-local static lib (recommended)

`shard.yml` runs `make` on install, producing `ext/libuw.a`. The binding's
`@[Link]` adds `-L<shard>/ext`, so `crystal build`/`crystal spec` from your
project link it automatically. To pin a non-default cap, run `make UW_CAP=0`
(or set it in your own build step) before compiling. Nothing needs to be
installed system-wide, and the result is statically linked into your binary.

## Build / link — approach B: system install

Build and install a shared or static `libuw` into a standard location
(`/usr/local/lib` + `/usr/local/include`), register it with `pkg-config` or
`ldconfig`, then drop the `ldflags` from the `@[Link]` annotation so it
resolves via the normal library search path / pkg-config:

    @[Link("uw")]
    lib LibUW
      # ...
    end

Approach A keeps the dependency vendored and reproducible; approach B suits a
library already packaged for the target system.

## Usage

```crystal
require "uw"

Uw.string_width("a世b")          # => 4
Uw.width('世')                   # => 2
Uw.width(0x07)                   # => nil (control)
Uw.graphemes("e\u0301x")         # => ["é", "x"]
Uw.next_grapheme_size("🇯🇵!")     # => bytes of the flag
Uw.string_width("a\ab", Uw::Control::Fail) # => nil

seg = Uw::Segmenter.new
seg.break_before?('e')           # => true
seg.break_before?(0x0301)        # => false

cw = Uw::ClusterWidth.new
cw.push('世').width              # => 2
```

All measuring methods accept `String`, `Bytes`, or `Slice(UInt32)`; UTF-8
inputs take an optional `Uw::Utf8` policy (`Replace` default, or `Strict`).