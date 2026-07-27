# src/uw.cr

require "./uw/tables"

module UW
  VERSION = "1.0.0"

  {% unless @top_level.has_constant?("CLUSTER_WIDTH_CAP") %}
    CLUSTER_WIDTH_CAP = 2
  {% end %}

  enum CtrlPolicy
    Skip = 0
    Fail = 1
  end

  enum Utf8Policy
    Replace = 0
    Strict  = 1
  end

  VS15 = 0xFE0E_u32
  VS16 = 0xFE0F_u32

  GCB_OTHER       =  0_u8
  GCB_CR          =  1_u8
  GCB_LF          =  2_u8
  GCB_CONTROL     =  3_u8
  GCB_EXTEND      =  4_u8
  GCB_ZWJ         =  5_u8
  GCB_PREPEND     =  6_u8
  GCB_SPACINGMARK =  7_u8
  GCB_L           =  8_u8
  GCB_V           =  9_u8
  GCB_T           = 10_u8
  GCB_LV          = 11_u8
  GCB_LVT         = 12_u8
  GCB_RI          = 13_u8

  INCB_NONE      = 0
  INCB_CONSONANT = 1
  INCB_EXTEND    = 2
  INCB_LINKER    = 3

  def self.unicode_version : String
    UNICODE_VERSION
  end

  @[AlwaysInline]
  def self.props(cp : UInt32) : UInt16
    return 0_u16 if cp >= (STAGE1_LEN.to_u32 << BLOCK_BITS)
    STAGE2[STAGE1.to_unsafe[cp >> BLOCK_BITS].to_i32 * BLOCK_SIZE + (cp & (BLOCK_SIZE - 1)).to_i32]
  end

  @[AlwaysInline]
  def self.prop_width(p : UInt16) : Int32
    (p & 0x3).to_i32
  end

  @[AlwaysInline]
  def self.prop_gcb(p : UInt16) : UInt8
    ((p >> 2) & 0xF).to_u8
  end

  @[AlwaysInline]
  def self.prop_pict?(p : UInt16) : Bool
    (p & 0x40) != 0
  end

  @[AlwaysInline]
  def self.prop_epres?(p : UInt16) : Bool
    (p & 0x80) != 0
  end

  @[AlwaysInline]
  def self.prop_incb(p : UInt16) : Int32
    ((p >> 8) & 0x3).to_i32
  end

  def self.width_cp(cp : UInt32) : Int32
    w = prop_width(props(cp))
    w == 3 ? -1 : w
  end

  struct State
    property prev_gcb : UInt8
    property ri_parity : UInt8
    property saw_pict : Bool
    property zwj_after_pict : Bool
    property incb_consonant : Bool
    property incb_linker_seen : Bool
    property has_prev : Bool

    def initialize
      @prev_gcb = GCB_OTHER
      @ri_parity = 0_u8
      @saw_pict = false
      @zwj_after_pict = false
      @incb_consonant = false
      @incb_linker_seen = false
      @has_prev = false
    end

    def reset : Nil
      @prev_gcb = GCB_OTHER
      @ri_parity = 0_u8
      @saw_pict = false
      @zwj_after_pict = false
      @incb_consonant = false
      @incb_linker_seen = false
      @has_prev = false
    end

    def grapheme_break(cp : UInt32) : Bool
      p = UW.props(cp)
      gcb = UW.prop_gcb(p)
      pict = UW.prop_pict?(p)
      incb = UW.prop_incb(p)

      if !@has_prev
        brk = true
      else
        a = @prev_gcb
        b = gcb
        if a == GCB_CR && b == GCB_LF
          brk = false
        elsif a == GCB_CONTROL || a == GCB_CR || a == GCB_LF
          brk = true
        elsif b == GCB_CONTROL || b == GCB_CR || b == GCB_LF
          brk = true
        elsif a == GCB_L && (b == GCB_L || b == GCB_V || b == GCB_LV || b == GCB_LVT)
          brk = false
        elsif (a == GCB_LV || a == GCB_V) && (b == GCB_V || b == GCB_T)
          brk = false
        elsif (a == GCB_LVT || a == GCB_T) && b == GCB_T
          brk = false
        elsif b == GCB_EXTEND || b == GCB_ZWJ
          brk = false
        elsif b == GCB_SPACINGMARK
          brk = false
        elsif a == GCB_PREPEND
          brk = false
        elsif incb == INCB_CONSONANT && @incb_consonant && @incb_linker_seen
          brk = false
        elsif @zwj_after_pict && pict
          brk = false
        elsif a == GCB_RI && b == GCB_RI && (@ri_parity & 1) != 0
          brk = false
        else
          brk = true
        end
      end

      if gcb == GCB_RI
        @ri_parity ^= 1_u8
      else
        @ri_parity = 0_u8
      end

      if pict
        @saw_pict = true
        @zwj_after_pict = false
      elsif gcb == GCB_EXTEND
        @zwj_after_pict = false
      elsif gcb == GCB_ZWJ
        @zwj_after_pict = @saw_pict
      else
        @saw_pict = false
        @zwj_after_pict = false
      end

      if incb == INCB_CONSONANT
        @incb_consonant = true
        @incb_linker_seen = false
      elsif incb == INCB_LINKER
        @incb_linker_seen = true if @incb_consonant
      elsif incb == INCB_EXTEND
        # keeps the sequence alive; no change
      else
        @incb_consonant = false
        @incb_linker_seen = false
      end

      @prev_gcb = gcb
      @has_prev = true
      brk
    end
  end

  struct Cluster
    property width : Int32
    property started : Bool
    property base_narrow_emoji : Bool
    property ri_count : UInt8

    def initialize
      @width = 0
      @started = false
      @base_narrow_emoji = false
      @ri_count = 0_u8
    end

    def reset : Nil
      @width = 0
      @started = false
      @base_narrow_emoji = false
      @ri_count = 0_u8
    end

    def push(cp : UInt32) : Nil
      p = UW.props(cp)
      gcb = UW.prop_gcb(p)
      w = UW.prop_width(p)

      if gcb == GCB_RI
        @ri_count += 1
        if !@started
          @width = 1
          @started = true
        end
        @width = 2 if @ri_count == 2
        return
      end

      if cp == VS16
        @width = 2 if @base_narrow_emoji
        return
      end
      if cp == VS15
        @width = 1 if @base_narrow_emoji
        return
      end

      if !@started
        @started = true
        @width = (w == 3) ? -1 : w
        @base_narrow_emoji = true if !UW.prop_epres?(p) && w != 2
      end
    end

    def display_width : Int32
      return -1 if @width < 0
      {% if CLUSTER_WIDTH_CAP > 0 %}
        @width > CLUSTER_WIDTH_CAP ? CLUSTER_WIDTH_CAP : @width
      {% else %}
        @width
      {% end %}
    end
  end

  @[AlwaysInline]
  private def self.utf8_decode(s : Pointer(UInt8), n : Int32) : {UInt32, Int32, Bool}
    c = s[0]
    return {c.to_u32, 1, false} if c < 0x80

    if (c & 0xE0) == 0xC0
      len = 2
      min = 0x80_u32
      acc = (c & 0x1F).to_u32
    elsif (c & 0xF0) == 0xE0
      len = 3
      min = 0x800_u32
      acc = (c & 0x0F).to_u32
    elsif (c & 0xF8) == 0xF0
      len = 4
      min = 0x10000_u32
      acc = (c & 0x07).to_u32
    else
      return {0xFFFD_u32, 1, true}
    end

    return {0xFFFD_u32, 1, true} if len > n

    i = 1
    while i < len
      ci = s[i]
      return {0xFFFD_u32, 1, true} if (ci & 0xC0) != 0x80
      acc = (acc << 6) | (ci & 0x3F).to_u32
      i += 1
    end

    if acc < min || acc > 0x10FFFF_u32 || (acc >= 0xD800_u32 && acc <= 0xDFFF_u32)
      return {0xFFFD_u32, 1, true}
    end
    {acc, len, false}
  end

  def self.width(cps : Slice(UInt32)) : {Int32, Int32}
    n = cps.size
    if n == 0
      return {0, 0}
    end
    st = State.new
    cl = Cluster.new
    ptr = cps.to_unsafe
    i = 0
    while i < n
      break if st.grapheme_break(ptr[i]) && cl.started
      cl.push(ptr[i])
      i += 1
    end
    {cl.display_width, i}
  end

  def self.width(s : Bytes, policy : Utf8Policy = Utf8Policy::Replace) : {Int32, Int32}
    n = s.size
    if n == 0
      return {0, 0}
    end
    st = State.new
    cl = Cluster.new
    ptr = s.to_unsafe
    i = 0
    while i < n
      cp, len, bad = utf8_decode(ptr + i, n - i)
      break if bad && policy.strict?
      break if st.grapheme_break(cp) && cl.started
      cl.push(cp)
      i += len
    end
    {cl.display_width, i}
  end

  def self.width(s : String, policy : Utf8Policy = Utf8Policy::Replace) : {Int32, Int32}
    width(s.to_slice, policy)
  end

  def self.grapheme_next(cps : Slice(UInt32)) : Int32
    _, consumed = width(cps)
    consumed
  end

  def self.grapheme_next(s : Bytes, policy : Utf8Policy = Utf8Policy::Replace) : Int32
    _, consumed = width(s, policy)
    consumed
  end

  def self.grapheme_next(s : String, policy : Utf8Policy = Utf8Policy::Replace) : Int32
    grapheme_next(s.to_slice, policy)
  end

  def self.swidth(cps : Slice(UInt32), ctrl : CtrlPolicy = CtrlPolicy::Skip) : Int32
    st = State.new
    cl = Cluster.new
    total = 0
    have_cluster = false
    ptr = cps.to_unsafe
    n = cps.size

    i = 0
    while i < n
      cp = ptr[i]
      if st.grapheme_break(cp) && have_cluster
        w = cl.display_width
        if w < 0
          return -1 if ctrl.fail?
        else
          total += w
        end
        cl.reset
      end
      cl.push(cp)
      have_cluster = true
      i += 1
    end
    if have_cluster
      w = cl.display_width
      if w < 0
        return -1 if ctrl.fail?
      else
        total += w
      end
    end
    total
  end

  def self.swidth(s : Bytes, upolicy : Utf8Policy = Utf8Policy::Replace, ctrl : CtrlPolicy = CtrlPolicy::Skip) : Int32
    st = State.new
    cl = Cluster.new
    total = 0
    have_cluster = false
    ptr = s.to_unsafe
    n = s.size

    i = 0
    while i < n
      cp, len, bad = utf8_decode(ptr + i, n - i)
      break if bad && upolicy.strict?
      if st.grapheme_break(cp) && have_cluster
        w = cl.display_width
        if w < 0
          return -1 if ctrl.fail?
        else
          total += w
        end
        cl.reset
      end
      cl.push(cp)
      have_cluster = true
      i += len
    end
    if have_cluster
      w = cl.display_width
      if w < 0
        return -1 if ctrl.fail?
      else
        total += w
      end
    end
    total
  end

  def self.swidth(s : String, upolicy : Utf8Policy = Utf8Policy::Replace, ctrl : CtrlPolicy = CtrlPolicy::Skip) : Int32
    swidth(s.to_slice, upolicy, ctrl)
  end
end
