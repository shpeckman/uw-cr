# src/uw.cr

require "./uw/lib_uw"

# Unicode display-width and grapheme-cluster segmentation.
#
# Thin, zero-copy bindings over the header-only `uw` C library (Unicode
# 17.0.0). Every call is synchronous, reentrant, and thread-safe: the only
# mutable state lives in caller-owned `Uw::Segmenter` / `Uw::ClusterWidth`
# values, which wrap C structs on the stack. Buffers are passed by pointer
# and length; no copies into C-owned memory are made, so these are safe to
# call from any fiber without interacting with the event loop.
module Uw
  VERSION = "1.0.0"

  # Handling for control characters when measuring a whole string.
  enum Control
    # Controls contribute 0; the width is the sum of printable clusters.
    Skip = 0
    # Any control makes the whole string measure as invalid (POSIX
    # `wcswidth` semantics), surfaced as `nil` from `string_width`.
    Fail = 1

    def to_unsafe : LibUW::CtrlPolicy
      LibUW::CtrlPolicy.new(value)
    end
  end

  # Handling for malformed UTF-8.
  enum Utf8
    # Malformed/truncated/overlong/surrogate bytes become U+FFFD and one
    # byte is consumed. Never reads past the given length.
    Replace = 0
    # Stop at the first malformed sequence; report what was consumed.
    Strict = 1

    def to_unsafe : LibUW::Utf8Policy
      LibUW::Utf8Policy.new(value)
    end
  end

  # Unicode version the lookup tables were generated from, e.g. `"17.0.0"`.
  def self.unicode_version : String
    String.new(LibUW.uw_unicode_version)
  end

  # The cluster-width cap this library was compiled with (2 by default, or
  # 0 for no cap). Callers that reason about caps must read this rather than
  # assume, since it is fixed at C build time.
  def self.active_width_cap : Int32
    LibUW.uw_active_width_cap
  end

  # Display width of a single code point: `0`, `1`, or `2`, or `nil` for a
  # control code (the C `-1` sentinel).
  def self.width(cp : Char) : Int32?
    raw = LibUW.uw_width_cp(cp.ord.to_u32)
    raw < 0 ? nil : raw.to_i
  end

  # :ditto:
  def self.width(cp : Int) : Int32?
    raw = LibUW.uw_width_cp(cp.to_u32)
    raw < 0 ? nil : raw.to_i
  end

  # Display width of the first grapheme cluster in *string*, plus the number
  # of bytes it spans. Returns width `nil` for a lone control cluster.
  def self.first_cluster_width(string : String, policy : Utf8 = Utf8::Replace) : {Int32?, Int32}
    w = LibUW.uw_width_utf8(string.to_unsafe, string.bytesize, out consumed, policy)
    { (w < 0 ? nil : w.to_i), consumed.to_i }
  end

  # Display width of the first grapheme cluster in *bytes* (assumed UTF-8),
  # plus the number of bytes it spans.
  def self.first_cluster_width(bytes : Bytes, policy : Utf8 = Utf8::Replace) : {Int32?, Int32}
    w = LibUW.uw_width_utf8(bytes.to_unsafe, bytes.size, out consumed, policy)
    { (w < 0 ? nil : w.to_i), consumed.to_i }
  end

  # Display width of the first grapheme cluster in a code-point slice, plus
  # the number of code points it spans.
  def self.first_cluster_width(cps : Slice(UInt32)) : {Int32?, Int32}
    w = LibUW.uw_width_cps(cps.to_unsafe, cps.size, out consumed)
    { (w < 0 ? nil : w.to_i), consumed.to_i }
  end

  # Byte length of the next grapheme starting at the front of *string*.
  # `0` when *string* is empty; always at least one byte under `Replace`.
  def self.next_grapheme_size(string : String, policy : Utf8 = Utf8::Replace) : Int32
    LibUW.uw_grapheme_next_utf8(string.to_unsafe, string.bytesize, policy).to_i
  end

  # :ditto:
  def self.next_grapheme_size(bytes : Bytes, policy : Utf8 = Utf8::Replace) : Int32
    LibUW.uw_grapheme_next_utf8(bytes.to_unsafe, bytes.size, policy).to_i
  end

  # Code-point count of the next grapheme starting at the front of *cps*.
  def self.next_grapheme_size(cps : Slice(UInt32)) : Int32
    LibUW.uw_grapheme_next_cps(cps.to_unsafe, cps.size).to_i
  end

  # Total display width of *string*, summing every grapheme cluster.
  # Returns `nil` only when *control* is `Control::Fail` and a control
  # character is present.
  def self.string_width(string : String, control : Control = Control::Skip,
                        policy : Utf8 = Utf8::Replace) : Int32?
    w = LibUW.uw_swidth_utf8(string.to_unsafe, string.bytesize, policy, control)
    w < 0 ? nil : w.to_i
  end

  # :ditto:
  def self.string_width(bytes : Bytes, control : Control = Control::Skip,
                        policy : Utf8 = Utf8::Replace) : Int32?
    w = LibUW.uw_swidth_utf8(bytes.to_unsafe, bytes.size, policy, control)
    w < 0 ? nil : w.to_i
  end

  # Total display width of a code-point slice.
  def self.string_width(cps : Slice(UInt32), control : Control = Control::Skip) : Int32?
    w = LibUW.uw_swidth_cps(cps.to_unsafe, cps.size, control)
    w < 0 ? nil : w.to_i
  end

  # Iterate the grapheme clusters of *string*, yielding each as a substring.
  def self.each_grapheme(string : String, policy : Utf8 = Utf8::Replace, &) : Nil
    ptr = string.to_unsafe
    rest = string.bytesize
    off = 0
    while rest > 0
      step = LibUW.uw_grapheme_next_utf8(ptr + off, rest, policy).to_i
      break if step == 0
      yield String.new(ptr + off, step)
      off += step
      rest -= step
    end
  end

  # Collect the grapheme clusters of *string* into an array of substrings.
  def self.graphemes(string : String, policy : Utf8 = Utf8::Replace) : Array(String)
    out = [] of String
    each_grapheme(string, policy) { |g| out << g }
    out
  end

  # Streaming grapheme-boundary state machine.
  #
  # Wraps the C `uw_state` on the stack. Feed code points in order; each
  # `#break_before?` reports whether a cluster boundary falls immediately
  # before the given code point. Drive this straight from a terminal input
  # path across buffer reads by keeping one `Segmenter` alive.
  struct Segmenter
    @st : LibUW::State

    def initialize
      @st = uninitialized LibUW::State
      LibUW.uw_state_init(pointerof(@st))
    end

    # Reset to the initial state, reusing the same storage.
    def reset : self
      LibUW.uw_state_init(pointerof(@st))
      self
    end

    # `true` if a grapheme boundary falls immediately before *cp*.
    def break_before?(cp : Char) : Bool
      LibUW.uw_grapheme_break(pointerof(@st), cp.ord.to_u32) != 0
    end

    # :ditto:
    def break_before?(cp : Int) : Bool
      LibUW.uw_grapheme_break(pointerof(@st), cp.to_u32) != 0
    end
  end

  # Streaming cluster-width accumulator.
  #
  # Wraps the C `uw_cluster` on the stack. Push the code points of one
  # grapheme, then read `#width`. Reuse across clusters with `#reset`.
  struct ClusterWidth
    @cl : LibUW::Cluster

    def initialize
      @cl = uninitialized LibUW::Cluster
      LibUW.uw_cluster_init(pointerof(@cl))
    end

    # Reset to an empty cluster, reusing the same storage.
    def reset : self
      LibUW.uw_cluster_init(pointerof(@cl))
      self
    end

    # Add a code point to the current cluster.
    def push(cp : Char) : self
      LibUW.uw_cluster_push(pointerof(@cl), cp.ord.to_u32)
      self
    end

    # :ditto:
    def push(cp : Int) : self
      LibUW.uw_cluster_push(pointerof(@cl), cp.to_u32)
      self
    end

    # Current cluster width, or `nil` for a control cluster.
    def width : Int32?
      w = LibUW.uw_cluster_width(pointerof(@cl))
      w < 0 ? nil : w.to_i
    end
  end
end