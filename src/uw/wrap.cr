# src/uw/wrap.cr

module UW
  record Line, offset : Int32, size : Int32, width : Int32, mandatory : Bool

  struct WrapOpts
    getter width : WidthOpts
    getter break_overlong : Bool
    getter trim : Bool

    def initialize(@width : WidthOpts = WidthOpts.unicode, @break_overlong : Bool = true, @trim : Bool = true)
    end

    def self.unicode : WrapOpts
      new(WidthOpts.unicode)
    end

    def self.legacy : WrapOpts
      new(WidthOpts.legacy)
    end

    def with_width(width : WidthOpts) : WrapOpts
      WrapOpts.new(width, @break_overlong, @trim)
    end

    def with_break_overlong(flag : Bool) : WrapOpts
      WrapOpts.new(@width, flag, @trim)
    end

    def with_trim(flag : Bool) : WrapOpts
      WrapOpts.new(@width, @break_overlong, flag)
    end
  end

  @[AlwaysInline]
  protected def self.trimmable?(cls : UInt8) : Bool
    cls == LB_SP || cls == LB_BK || cls == LB_CR || cls == LB_LF || cls == LB_NL
  end

  struct Utf32Wrap
    def initialize(@cps : Slice(UInt32), @cols : Int32, @opts : WrapOpts = WrapOpts.new)
      @lb         = Utf32LineBreaks.new(@cps, @opts.width)
      @cursor     = 0
      @p_off      = 0
      @p_size     = 0
      @p_width    = 0
      @p_tsize    = 0
      @p_twidth   = 0
      @p_mand     = false
      @p_valid    = false
      @line_off   = 0
      @acc_size   = 0
      @acc_width  = 0
      @acc_tsize  = 0
      @acc_twidth = 0
      @has_line   = false
      @acc_mand   = false
    end

    def reset(cps : Slice(UInt32), cols : Int32 = @cols, opts : WrapOpts = @opts) : Nil
      @cps  = cps
      @cols = cols
      @opts = opts
      @lb.reset(cps, opts.width)
      @cursor     = 0
      @p_off      = 0
      @p_size     = 0
      @p_width    = 0
      @p_tsize    = 0
      @p_twidth   = 0
      @p_mand     = false
      @p_valid    = false
      @line_off   = 0
      @acc_size   = 0
      @acc_width  = 0
      @acc_tsize  = 0
      @acc_twidth = 0
      @has_line   = false
      @acc_mand   = false
    end

    private def measure(off : Int32, size : Int32) : {Int32, Int32, Int32}
      w      = 0
      tw     = 0
      ts     = 0
      cur    = 0
      it     = Utf32Clusters.new(@cps[off, size], @opts.width)
      it.each do |span|
        cw = span.width < 0 ? 0 : span.width
        w += cw
        cur += span.size
        cls = UW::Props.lb(UW::Props.props(@cps[off + cur - span.size]))
        unless UW.trimmable?(cls)
          tw = w
          ts = cur
        end
      end
      {w, ts, tw}
    end

    private def load : Bool
      return true if @p_valid
      span = @lb.next?
      return false unless span
      w, ts, tw = measure(@cursor, span.size)
      @p_off    = @cursor
      @p_size   = span.size
      @p_width  = w
      @p_tsize  = ts
      @p_twidth = tw
      @p_mand   = span.mandatory
      @p_valid  = true
      @cursor += span.size
      true
    end

    private def accumulate : Nil
      @line_off = @p_off unless @has_line
      if @p_tsize > 0
        @acc_tsize  = @acc_size + @p_tsize
        @acc_twidth = @acc_width + @p_twidth
      end
      @acc_size += @p_size
      @acc_width += @p_width
      @acc_mand = @p_mand
      @has_line = true
      @p_valid  = false
    end

    private def emit : Line
      size  = @opts.trim ? @acc_tsize : @acc_size
      width = @opts.trim ? @acc_twidth : @acc_width
      line  = Line.new(@line_off, size, width, @acc_mand)
      @acc_size   = 0
      @acc_width  = 0
      @acc_tsize  = 0
      @acc_twidth = 0
      @acc_mand   = false
      @has_line   = false
      line
    end

    def next? : Line?
      loop do
        unless load
          return @has_line ? emit : nil
        end

        if !@has_line && @cols > 0 && @p_twidth > @cols && @opts.break_overlong
          w, cut = UW.truncate(@cps[@p_off, @p_size], @cols, @opts.width)
          cut = UW.grapheme_next(@cps[@p_off, @p_size]) if cut <= 0
          if cut > 0 && cut < @p_size
            line = Line.new(@p_off, cut, w, false)
            @p_off += cut
            @p_size -= cut
            nw, nts, ntw = measure(@p_off, @p_size)
            @p_width  = nw
            @p_tsize  = nts
            @p_twidth = ntw
            return line
          end
        end

        if @has_line && @cols > 0 && @acc_width + @p_twidth > @cols
          return emit
        end

        accumulate
        return emit if @acc_mand
      end
    end

    def each(& : Line ->) : Nil
      while line = next?
        yield line
      end
    end
  end

  struct Utf8Wrap
    def initialize(@bytes : Bytes, @cols : Int32, @policy : Utf8Policy = Utf8Policy::Replace, @opts : WrapOpts = WrapOpts.new)
      @lb         = Utf8LineBreaks.new(@bytes, @policy, @opts.width)
      @cursor     = 0
      @p_off      = 0
      @p_size     = 0
      @p_width    = 0
      @p_tsize    = 0
      @p_twidth   = 0
      @p_mand     = false
      @p_valid    = false
      @line_off   = 0
      @acc_size   = 0
      @acc_width  = 0
      @acc_tsize  = 0
      @acc_twidth = 0
      @has_line   = false
      @acc_mand   = false
    end

    def reset(bytes : Bytes, cols : Int32 = @cols, policy : Utf8Policy = @policy, opts : WrapOpts = @opts) : Nil
      @bytes  = bytes
      @cols   = cols
      @policy = policy
      @opts   = opts
      @lb.reset(bytes, policy, opts.width)
      @cursor     = 0
      @p_off      = 0
      @p_size     = 0
      @p_width    = 0
      @p_tsize    = 0
      @p_twidth   = 0
      @p_mand     = false
      @p_valid    = false
      @line_off   = 0
      @acc_size   = 0
      @acc_width  = 0
      @acc_tsize  = 0
      @acc_twidth = 0
      @has_line   = false
      @acc_mand   = false
    end

    def reset(s : String, cols : Int32 = @cols, policy : Utf8Policy = @policy, opts : WrapOpts = @opts) : Nil
      reset(s.to_slice, cols, policy, opts)
    end

    private def measure(off : Int32, size : Int32) : {Int32, Int32, Int32}
      w   = 0
      tw  = 0
      ts  = 0
      cur = 0
      ptr = @bytes.to_unsafe
      it  = Utf8Clusters.new(@bytes[off, size], @policy, @opts.width)
      it.each do |span|
        cw = span.width < 0 ? 0 : span.width
        w += cw
        cur += span.size
        base     = off + cur - span.size
        cp, _, _ = UW.utf8_decode(ptr + base, @bytes.size - base)
        cls      = UW::Props.lb(UW::Props.props(cp))
        unless UW.trimmable?(cls)
          tw = w
          ts = cur
        end
      end
      {w, ts, tw}
    end

    private def load : Bool
      return true if @p_valid
      span = @lb.next?
      return false unless span
      w, ts, tw = measure(@cursor, span.size)
      @p_off    = @cursor
      @p_size   = span.size
      @p_width  = w
      @p_tsize  = ts
      @p_twidth = tw
      @p_mand   = span.mandatory
      @p_valid  = true
      @cursor += span.size
      true
    end

    private def accumulate : Nil
      @line_off = @p_off unless @has_line
      if @p_tsize > 0
        @acc_tsize  = @acc_size + @p_tsize
        @acc_twidth = @acc_width + @p_twidth
      end
      @acc_size += @p_size
      @acc_width += @p_width
      @acc_mand = @p_mand
      @has_line = true
      @p_valid  = false
    end

    private def emit : Line
      size  = @opts.trim ? @acc_tsize : @acc_size
      width = @opts.trim ? @acc_twidth : @acc_width
      line  = Line.new(@line_off, size, width, @acc_mand)
      @acc_size   = 0
      @acc_width  = 0
      @acc_tsize  = 0
      @acc_twidth = 0
      @acc_mand   = false
      @has_line   = false
      line
    end

    def next? : Line?
      loop do
        unless load
          return @has_line ? emit : nil
        end

        if !@has_line && @cols > 0 && @p_twidth > @cols && @opts.break_overlong
          w, cut = UW.truncate(@bytes[@p_off, @p_size], @cols, @policy, @opts.width)
          cut = UW.grapheme_next(@bytes[@p_off, @p_size], @policy) if cut <= 0
          if cut > 0 && cut < @p_size
            line = Line.new(@p_off, cut, w, false)
            @p_off += cut
            @p_size -= cut
            nw, nts, ntw = measure(@p_off, @p_size)
            @p_width  = nw
            @p_tsize  = nts
            @p_twidth = ntw
            return line
          end
        end

        if @has_line && @cols > 0 && @acc_width + @p_twidth > @cols
          return emit
        end

        accumulate
        return emit if @acc_mand
      end
    end

    def each(& : Line ->) : Nil
      while line = next?
        yield line
      end
    end
  end
end
