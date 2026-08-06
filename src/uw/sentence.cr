# src/uw/sentence.cr

module UW
  record SentenceSpan, width : Int32, size : Int32

  private TAIL_NONE  = 0_u8
  private TAIL_ATERM = 1_u8
  private TAIL_STERM = 2_u8

  struct SentenceState
    def initialize
      @has_prev = false
      @raw_prev = SB_OTHER
      @sig1     = SB_OTHER
      @sig2     = SB_OTHER
      @has_sig1 = false
      @has_sig2 = false
      @tail     = TAIL_NONE
      @tail_sp  = false
    end

    def reset : Nil
      @has_prev = false
      @raw_prev = SB_OTHER
      @sig1     = SB_OTHER
      @sig2     = SB_OTHER
      @has_sig1 = false
      @has_sig2 = false
      @tail     = TAIL_NONE
      @tail_sp  = false
    end

    def sentence_break(cp : UInt32, lower_ahead : Bool) : Bool
      sentence_break(cp, UW::Props.props(cp), lower_ahead)
    end

    def sentence_break(cp : UInt32, p : UInt32, lower_ahead : Bool) : Bool
      cur = UW::Props.sb(p)
      a   = @raw_prev

      ignorable = false

      if !@has_prev
        brk = true
      elsif a == SB_CR && cur == SB_LF
        brk = false
      elsif a == SB_SEP || a == SB_CR || a == SB_LF
        brk = true
      elsif cur == SB_EXTEND || cur == SB_FORMAT
        brk       = false
        ignorable = true
      else
        brk = core(cur, lower_ahead)
      end

      @raw_prev = cur
      @has_prev = true

      unless ignorable
        advance_tail(cur)
        @sig2     = @sig1
        @has_sig2 = @has_sig1
        @sig1     = cur
        @has_sig1 = true
      end

      brk
    end

    @[AlwaysInline]
    private def paragraph?(x : UInt8) : Bool
      x == SB_SEP || x == SB_CR || x == SB_LF
    end

    @[AlwaysInline]
    private def terminated? : Bool
      @tail != TAIL_NONE
    end

    private def advance_tail(cur : UInt8)
      if terminated?
        if cur == SB_CLOSE
          return unless @tail_sp
          @tail = TAIL_NONE
        elsif cur == SB_SP
          @tail_sp = true
          return
        elsif paragraph?(cur)
          @tail    = TAIL_NONE
          @tail_sp = false
          return
        else
          @tail    = TAIL_NONE
          @tail_sp = false
        end
      end

      if cur == SB_ATERM
        @tail    = TAIL_ATERM
        @tail_sp = false
      elsif cur == SB_STERM
        @tail    = TAIL_STERM
        @tail_sp = false
      end
    end

    private def core(cur : UInt8, lower_ahead : Bool) : Bool
      return true unless @has_sig1

      if @sig1 == SB_ATERM
        return false if cur == SB_NUMERIC
        return false if cur == SB_UPPER && @has_sig2 && (@sig2 == SB_UPPER || @sig2 == SB_LOWER)
      end

      if terminated?
        return false if @tail == TAIL_ATERM && lower_ahead
        return false if cur == SB_SCONTINUE || cur == SB_ATERM || cur == SB_STERM
        return false if cur == SB_CLOSE && !@tail_sp
        return false if cur == SB_SP
        return false if paragraph?(cur)
        return true
      end

      false
    end
  end

  struct Utf32Sentences
    def initialize(@cps : Slice(UInt32), @opts : WidthOpts = WidthOpts.unicode)
      @ptr       = @cps.to_unsafe
      @n         = @cps.size
      @i         = 0
      @st        = SentenceState.new
      @have_seed = false
      @seed_cp   = 0_u32
      @seed_p    = 0_u32
    end

    def reset(cps : Slice(UInt32), opts : WidthOpts = @opts) : Nil
      @cps  = cps
      @opts = opts
      @ptr  = cps.to_unsafe
      @n    = cps.size
      @i    = 0
      @st.reset
      @have_seed = false
      @seed_cp   = 0_u32
      @seed_p    = 0_u32
    end

    private def lower_ahead?(from : Int32) : Bool
      j = from
      while j < @n
        c = UW::Props.sb(UW::Props.props(@ptr[j]))
        case c
        when SB_LOWER
          return true
        when SB_OLETTER, SB_UPPER, SB_SEP, SB_CR, SB_LF, SB_STERM, SB_ATERM
          return false
        else
          j += 1
        end
      end
      false
    end

    def next? : SentenceSpan?
      return nil if @i >= @n && !@have_seed

      start    = @i
      consumed = 0

      if @have_seed
        start = @i - 1
        consumed += 1
        @have_seed = false
      end

      while @i < @n
        cp = @ptr[@i]
        p  = UW::Props.props(cp)
        la = lower_ahead?(@i)
        if @st.sentence_break(cp, p, la) && consumed > 0
          @seed_cp   = cp
          @seed_p    = p
          @have_seed = true
          @i += 1
          return SentenceSpan.new(UW.swidth(@cps[start, consumed], CtrlPolicy::Skip, @opts), consumed)
        end
        consumed += 1
        @i += 1
      end

      return nil if consumed == 0
      SentenceSpan.new(UW.swidth(@cps[start, consumed], CtrlPolicy::Skip, @opts), consumed)
    end

    def each(& : SentenceSpan ->) : Nil
      while span = next?
        yield span
      end
    end
  end

  struct Utf8Sentences
    def initialize(@bytes : Bytes, @policy : Utf8Policy = Utf8Policy::Replace, @opts : WidthOpts = WidthOpts.unicode)
      @ptr       = @bytes.to_unsafe
      @n         = @bytes.size
      @i         = 0
      @st        = SentenceState.new
      @have_seed = false
      @seed_len  = 0
    end

    def reset(bytes : Bytes, policy : Utf8Policy = @policy, opts : WidthOpts = @opts) : Nil
      @bytes  = bytes
      @policy = policy
      @opts   = opts
      @ptr    = bytes.to_unsafe
      @n      = bytes.size
      @i      = 0
      @st.reset
      @have_seed = false
      @seed_len  = 0
    end

    def reset(s : String, policy : Utf8Policy = @policy, opts : WidthOpts = @opts) : Nil
      reset(s.to_slice, policy, opts)
    end

    private def lower_ahead?(from : Int32) : Bool
      j = from
      while j < @n
        cp, len, bad = UW.utf8_decode(@ptr + j, @n - j)
        return false if bad && @policy.strict?
        c = UW::Props.sb(UW::Props.props(cp))
        case c
        when SB_LOWER
          return true
        when SB_OLETTER, SB_UPPER, SB_SEP, SB_CR, SB_LF, SB_STERM, SB_ATERM
          return false
        else
          j += len
        end
      end
      false
    end

    def next? : SentenceSpan?
      return nil if @i >= @n && !@have_seed

      start    = @i
      consumed = 0

      if @have_seed
        start = @i - @seed_len
        consumed += @seed_len
        @have_seed = false
      end

      while @i < @n
        cp, len, bad = UW.utf8_decode(@ptr + @i, @n - @i)
        break if bad && @policy.strict?
        p  = UW::Props.props(cp)
        la = lower_ahead?(@i)
        if @st.sentence_break(cp, p, la) && consumed > 0
          @seed_len  = len
          @have_seed = true
          @i += len
          return SentenceSpan.new(UW.swidth(@bytes[start, consumed], @policy, CtrlPolicy::Skip, @opts), consumed)
        end
        consumed += len
        @i += len
      end

      return nil if consumed == 0
      SentenceSpan.new(UW.swidth(@bytes[start, consumed], @policy, CtrlPolicy::Skip, @opts), consumed)
    end

    def each(& : SentenceSpan ->) : Nil
      while span = next?
        yield span
      end
    end
  end
end