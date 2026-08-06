# src/uw/linebreak.cr

module UW
  record BreakSpan, width : Int32, size : Int32, mandatory : Bool

  enum LineAction
    NoBreak   = 0
    Break     = 1
    Mandatory = 2
  end

  private LB_F_PI     =  1_u8
  private LB_F_PF     =  2_u8
  private LB_F_EA     =  4_u8
  private LB_F_PICTCN =  8_u8
  private LB_F_DOTC   = 16_u8

  struct LineUnit
    getter cls      : UInt8
    getter flags    : UInt8
    getter size     : Int32
    getter ends_zwj : Bool

    def initialize(@cls : UInt8 = LB_SOT, @flags : UInt8 = 0_u8, @size : Int32 = 0, @ends_zwj : Bool = false)
    end

    @[AlwaysInline]
    def pi? : Bool
      (@flags & LB_F_PI) != 0
    end

    @[AlwaysInline]
    def pf? : Bool
      (@flags & LB_F_PF) != 0
    end

    @[AlwaysInline]
    def east_asian? : Bool
      (@flags & LB_F_EA) != 0
    end

    @[AlwaysInline]
    def pict_unassigned? : Bool
      (@flags & LB_F_PICTCN) != 0
    end

    @[AlwaysInline]
    def dotted_circle? : Bool
      (@flags & LB_F_DOTC) != 0
    end

    @[AlwaysInline]
    def ak? : Bool
      @cls == LB_AK || @cls == LB_AS || dotted_circle?
    end

    @[AlwaysInline]
    def ak_dot? : Bool
      @cls == LB_AK || dotted_circle?
    end
  end

  @[AlwaysInline]
  protected def self.lb_flags(p : UInt32) : UInt8
    f = 0_u8
    f |= LB_F_PI if UW::Props.pi?(p)
    f |= LB_F_PF if UW::Props.pf?(p)
    f |= LB_F_EA if UW::Props.east_asian?(p)
    f |= LB_F_PICTCN if UW::Props.pict_unassigned?(p)
    f |= LB_F_DOTC if UW::Props.dotted_circle?(p)
    f
  end

  struct LineState
    def initialize
      @p1        = LineUnit.new
      @p2        = LineUnit.new
      @nonsp     = LineUnit.new
      @has_p1    = false
      @has_p2    = false
      @has_nonsp = false
      @zw_run    = false
      @lb15a     = false
      @nu_seq    = false
      @nu_clcp   = false
      @ri_run    = 0
    end

    def reset : Nil
      @p1        = LineUnit.new
      @p2        = LineUnit.new
      @nonsp     = LineUnit.new
      @has_p1    = false
      @has_p2    = false
      @has_nonsp = false
      @zw_run    = false
      @lb15a     = false
      @nu_seq    = false
      @nu_clcp   = false
      @ri_run    = 0
    end

    def consume(u : LineUnit) : Nil
      if u.cls == LB_QU && u.pi? && (!@has_p1 || opener?(@p1.cls))
        @lb15a = true
      elsif u.cls != LB_SP
        @lb15a = false
      end

      if u.cls == LB_ZW
        @zw_run = true
      elsif u.cls != LB_SP
        @zw_run = false
      end

      if u.cls == LB_RI
        @ri_run += 1
      else
        @ri_run = 0
      end

      if u.cls == LB_NU
        @nu_seq  = true
        @nu_clcp = false
      elsif @nu_seq && (u.cls == LB_SY || u.cls == LB_IS)
        @nu_clcp = false
      elsif @nu_seq && (u.cls == LB_CL || u.cls == LB_CP)
        @nu_seq  = false
        @nu_clcp = true
      else
        @nu_seq  = false
        @nu_clcp = false
      end

      unless u.cls == LB_SP
        @nonsp     = u
        @has_nonsp = true
      end

      @p2     = @p1
      @has_p2 = @has_p1
      @p1     = u
      @has_p1 = true
    end

    @[AlwaysInline]
    private def opener?(c : UInt8) : Bool
      c == LB_BK || c == LB_CR || c == LB_LF || c == LB_NL ||
        c == LB_OP || c == LB_QU || c == LB_GL || c == LB_SP || c == LB_ZW
    end

    @[AlwaysInline]
    private def alhl?(c : UInt8) : Bool
      c == LB_AL || c == LB_HL
    end

    @[AlwaysInline]
    private def jamo?(c : UInt8) : Bool
      c == LB_JL || c == LB_JV || c == LB_JT || c == LB_H2 || c == LB_H3
    end

    def decide(b : LineUnit, n1 : LineUnit, has1 : Bool, n2 : LineUnit, has2 : Bool) : LineAction
      return LineAction::NoBreak unless @has_p1
      a = @p1

      return LineAction::Mandatory if a.cls == LB_BK
      return LineAction::NoBreak if a.cls == LB_CR && b.cls == LB_LF
      return LineAction::Mandatory if a.cls == LB_CR || a.cls == LB_LF || a.cls == LB_NL
      return LineAction::NoBreak if b.cls == LB_BK || b.cls == LB_CR || b.cls == LB_LF || b.cls == LB_NL
      return LineAction::NoBreak if b.cls == LB_SP || b.cls == LB_ZW
      return LineAction::Break if @zw_run
      return LineAction::NoBreak if a.ends_zwj
      return LineAction::NoBreak if b.cls == LB_WJ || a.cls == LB_WJ
      return LineAction::NoBreak if a.cls == LB_GL

      if b.cls == LB_GL && !(a.cls == LB_SP || a.cls == LB_BA || a.cls == LB_HY || a.cls == LB_HH)
        return LineAction::NoBreak
      end

      return LineAction::NoBreak if b.cls == LB_CL || b.cls == LB_CP || b.cls == LB_EX || b.cls == LB_SY
      return LineAction::NoBreak if @has_nonsp && @nonsp.cls == LB_OP
      return LineAction::NoBreak if @lb15a

      if b.cls == LB_QU && b.pf?
        return LineAction::NoBreak unless has1
        c = n1.cls
        if c == LB_SP || c == LB_GL || c == LB_WJ || c == LB_CL || c == LB_QU ||
           c == LB_CP || c == LB_EX || c == LB_IS || c == LB_SY || c == LB_BK ||
           c == LB_CR || c == LB_LF || c == LB_NL || c == LB_ZW
          return LineAction::NoBreak
        end
      end

      return LineAction::Break if a.cls == LB_SP && b.cls == LB_IS && has1 && n1.cls == LB_NU
      return LineAction::NoBreak if b.cls == LB_IS
      return LineAction::NoBreak if @has_nonsp && (@nonsp.cls == LB_CL || @nonsp.cls == LB_CP) && b.cls == LB_NS
      return LineAction::NoBreak if @has_nonsp && @nonsp.cls == LB_B2 && b.cls == LB_B2
      return LineAction::Break if a.cls == LB_SP

      return LineAction::NoBreak if b.cls == LB_QU && !b.pi?
      return LineAction::NoBreak if a.cls == LB_QU && !a.pf?

      if b.cls == LB_QU
        return LineAction::NoBreak unless a.east_asian?
        return LineAction::NoBreak if !has1 || !n1.east_asian?
      end
      if a.cls == LB_QU
        return LineAction::NoBreak unless b.east_asian?
        return LineAction::NoBreak if !@has_p2 || !@p2.east_asian?
      end

      return LineAction::Break if b.cls == LB_CB || a.cls == LB_CB

      if (a.cls == LB_HY || a.cls == LB_HH) && alhl?(b.cls)
        return LineAction::NoBreak unless @has_p2
        c = @p2.cls
        if c == LB_BK || c == LB_CR || c == LB_LF || c == LB_NL ||
           c == LB_SP || c == LB_ZW || c == LB_CB || c == LB_GL
          return LineAction::NoBreak
        end
      end

      return LineAction::NoBreak if b.cls == LB_BA || b.cls == LB_HH || b.cls == LB_HY || b.cls == LB_NS
      return LineAction::NoBreak if a.cls == LB_BB

      if @has_p2 && @p2.cls == LB_HL && (a.cls == LB_HY || a.cls == LB_HH) && b.cls != LB_HL
        return LineAction::NoBreak
      end

      return LineAction::NoBreak if a.cls == LB_SY && b.cls == LB_HL
      return LineAction::NoBreak if b.cls == LB_IN
      return LineAction::NoBreak if alhl?(a.cls) && b.cls == LB_NU
      return LineAction::NoBreak if a.cls == LB_NU && alhl?(b.cls)
      return LineAction::NoBreak if a.cls == LB_PR && (b.cls == LB_ID || b.cls == LB_EB || b.cls == LB_EM)
      return LineAction::NoBreak if (a.cls == LB_ID || a.cls == LB_EB || a.cls == LB_EM) && b.cls == LB_PO
      return LineAction::NoBreak if (a.cls == LB_PR || a.cls == LB_PO) && alhl?(b.cls)
      return LineAction::NoBreak if alhl?(a.cls) && (b.cls == LB_PR || b.cls == LB_PO)

      if b.cls == LB_PO || b.cls == LB_PR
        return LineAction::NoBreak if @nu_clcp || @nu_seq
      end
      if (a.cls == LB_PO || a.cls == LB_PR) && b.cls == LB_OP
        return LineAction::NoBreak if has1 && n1.cls == LB_NU
        return LineAction::NoBreak if has1 && n1.cls == LB_IS && has2 && n2.cls == LB_NU
      end
      return LineAction::NoBreak if (a.cls == LB_PO || a.cls == LB_PR) && b.cls == LB_NU
      return LineAction::NoBreak if a.cls == LB_HY && b.cls == LB_NU
      return LineAction::NoBreak if a.cls == LB_IS && b.cls == LB_NU
      return LineAction::NoBreak if @nu_seq && b.cls == LB_NU

      return LineAction::NoBreak if a.cls == LB_JL && (b.cls == LB_JL || b.cls == LB_JV || b.cls == LB_H2 || b.cls == LB_H3)
      return LineAction::NoBreak if (a.cls == LB_JV || a.cls == LB_H2) && (b.cls == LB_JV || b.cls == LB_JT)
      return LineAction::NoBreak if (a.cls == LB_JT || a.cls == LB_H3) && b.cls == LB_JT
      return LineAction::NoBreak if jamo?(a.cls) && b.cls == LB_PO
      return LineAction::NoBreak if a.cls == LB_PR && jamo?(b.cls)

      return LineAction::NoBreak if alhl?(a.cls) && alhl?(b.cls)

      return LineAction::NoBreak if a.cls == LB_AP && b.ak?
      return LineAction::NoBreak if a.ak? && (b.cls == LB_VF || b.cls == LB_VI)
      if @has_p2 && @p2.ak? && a.cls == LB_VI && b.ak_dot?
        return LineAction::NoBreak
      end
      if a.ak? && b.ak? && has1 && n1.cls == LB_VF
        return LineAction::NoBreak
      end

      return LineAction::NoBreak if a.cls == LB_IS && alhl?(b.cls)
      return LineAction::NoBreak if (alhl?(a.cls) || a.cls == LB_NU) && b.cls == LB_OP && !b.east_asian?
      return LineAction::NoBreak if a.cls == LB_CP && !a.east_asian? && (alhl?(b.cls) || b.cls == LB_NU)
      return LineAction::NoBreak if b.cls == LB_RI && (@ri_run & 1) == 1
      return LineAction::NoBreak if a.cls == LB_EB && b.cls == LB_EM
      return LineAction::NoBreak if a.pict_unassigned? && b.cls == LB_EM

      LineAction::Break
    end
  end

  struct Utf32LineBreaks
    def initialize(@cps : Slice(UInt32), @opts : WidthOpts = WidthOpts.unicode)
      @ptr     = @cps.to_unsafe
      @n       = @cps.size
      @i       = 0
      @pos     = 0
      @st      = LineState.new
      @cur     = LineUnit.new
      @n1      = LineUnit.new
      @n2      = LineUnit.new
      @has_cur = false
      @has_n1  = false
      @has_n2  = false
      prime
    end

    def reset(cps : Slice(UInt32), opts : WidthOpts = @opts) : Nil
      @cps  = cps
      @opts = opts
      @ptr  = cps.to_unsafe
      @n    = cps.size
      @i    = 0
      @pos  = 0
      @st.reset
      @cur     = LineUnit.new
      @n1      = LineUnit.new
      @n2      = LineUnit.new
      @has_cur = false
      @has_n1  = false
      @has_n2  = false
      prime
    end

    private def prime : Nil
      u, ok = pull
      @cur, @has_cur = u, ok
      u, ok = pull
      @n1, @has_n1 = u, ok
      u, ok = pull
      @n2, @has_n2 = u, ok
    end

    private def advance : Nil
      @cur, @has_cur = @n1, @has_n1
      @n1, @has_n1 = @n2, @has_n2
      u, ok = pull
      @n2, @has_n2 = u, ok
    end

    private def pull : {LineUnit, Bool}
      return {LineUnit.new, false} if @i >= @n
      cp  = @ptr[@i]
      p   = UW::Props.props(cp)
      cls = UW::Props.lb(p)
      fl  = UW.lb_flags(p)
      sz  = 1
      ez  = false
      @i += 1

      if cls == LB_CM || cls == LB_ZWJ
        ez  = cls == LB_ZWJ
        cls = LB_AL
        fl  = 0_u8
      end

      unless cls == LB_BK || cls == LB_CR || cls == LB_LF ||
             cls == LB_NL || cls == LB_SP || cls == LB_ZW
        while @i < @n
          c2 = UW::Props.lb(UW::Props.props(@ptr[@i]))
          break unless c2 == LB_CM || c2 == LB_ZWJ
          ez = c2 == LB_ZWJ
          sz += 1
          @i += 1
        end
      end

      {LineUnit.new(cls, fl, sz, ez), true}
    end

    def next? : BreakSpan?
      return nil unless @has_cur
      start = @pos
      size  = 0
      mand  = false

      loop do
        unless @has_cur
          mand = true
          break
        end
        if size > 0
          act = @st.decide(@cur, @n1, @has_n1, @n2, @has_n2)
          unless act.no_break?
            mand = act.mandatory?
            break
          end
        end
        size += @cur.size
        @pos += @cur.size
        @st.consume(@cur)
        advance
      end

      return nil if size == 0
      BreakSpan.new(UW.swidth(@cps[start, size], CtrlPolicy::Skip, @opts), size, mand)
    end

    def each(& : BreakSpan ->) : Nil
      while span = next?
        yield span
      end
    end
  end

  struct Utf8LineBreaks
    def initialize(@bytes : Bytes, @policy : Utf8Policy = Utf8Policy::Replace, @opts : WidthOpts = WidthOpts.unicode)
      @ptr     = @bytes.to_unsafe
      @n       = @bytes.size
      @i       = 0
      @pos     = 0
      @st      = LineState.new
      @cur     = LineUnit.new
      @n1      = LineUnit.new
      @n2      = LineUnit.new
      @has_cur = false
      @has_n1  = false
      @has_n2  = false
      prime
    end

    def reset(bytes : Bytes, policy : Utf8Policy = @policy, opts : WidthOpts = @opts) : Nil
      @bytes  = bytes
      @policy = policy
      @opts   = opts
      @ptr    = bytes.to_unsafe
      @n      = bytes.size
      @i      = 0
      @pos    = 0
      @st.reset
      @cur     = LineUnit.new
      @n1      = LineUnit.new
      @n2      = LineUnit.new
      @has_cur = false
      @has_n1  = false
      @has_n2  = false
      prime
    end

    def reset(s : String, policy : Utf8Policy = @policy, opts : WidthOpts = @opts) : Nil
      reset(s.to_slice, policy, opts)
    end

    private def prime : Nil
      u, ok = pull
      @cur, @has_cur = u, ok
      u, ok = pull
      @n1, @has_n1 = u, ok
      u, ok = pull
      @n2, @has_n2 = u, ok
    end

    private def advance : Nil
      @cur, @has_cur = @n1, @has_n1
      @n1, @has_n1 = @n2, @has_n2
      u, ok = pull
      @n2, @has_n2 = u, ok
    end

    private def pull : {LineUnit, Bool}
      return {LineUnit.new, false} if @i >= @n
      cp, len, bad = UW.utf8_decode(@ptr + @i, @n - @i)
      return {LineUnit.new, false} if bad && @policy.strict?
      p   = UW::Props.props(cp)
      cls = UW::Props.lb(p)
      fl  = UW.lb_flags(p)
      sz  = len
      ez  = false
      @i += len

      if cls == LB_CM || cls == LB_ZWJ
        ez  = cls == LB_ZWJ
        cls = LB_AL
        fl  = 0_u8
      end

      unless cls == LB_BK || cls == LB_CR || cls == LB_LF ||
             cls == LB_NL || cls == LB_SP || cls == LB_ZW
        while @i < @n
          cp2, len2, bad2 = UW.utf8_decode(@ptr + @i, @n - @i)
          break if bad2 && @policy.strict?
          c2 = UW::Props.lb(UW::Props.props(cp2))
          break unless c2 == LB_CM || c2 == LB_ZWJ
          ez = c2 == LB_ZWJ
          sz += len2
          @i += len2
        end
      end

      {LineUnit.new(cls, fl, sz, ez), true}
    end

    def next? : BreakSpan?
      return nil unless @has_cur
      start = @pos
      size  = 0
      mand  = false

      loop do
        unless @has_cur
          mand = true
          break
        end
        if size > 0
          act = @st.decide(@cur, @n1, @has_n1, @n2, @has_n2)
          unless act.no_break?
            mand = act.mandatory?
            break
          end
        end
        size += @cur.size
        @pos += @cur.size
        @st.consume(@cur)
        advance
      end

      return nil if size == 0
      BreakSpan.new(UW.swidth(@bytes[start, size], @policy, CtrlPolicy::Skip, @opts), size, mand)
    end

    def each(& : BreakSpan ->) : Nil
      while span = next?
        yield span
      end
    end
  end
end
