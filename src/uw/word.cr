# src/uw/word.cr

module UW
  record WordSpan, width : Int32, size : Int32

  struct WordState
    def initialize
      @has_prev = false
      @raw_prev = WB_OTHER
      @sig1     = WB_OTHER
      @sig2     = WB_OTHER
      @has_sig1 = false
      @has_sig2 = false
      @ri_run   = 0
    end

    def reset : Nil
      @has_prev = false
      @raw_prev = WB_OTHER
      @sig1     = WB_OTHER
      @sig2     = WB_OTHER
      @has_sig1 = false
      @has_sig2 = false
      @ri_run   = 0
    end

    def word_break(cp : UInt32, nxt : UInt8, has_next : Bool) : Bool
      word_break(cp, UW::Props.props(cp), nxt, has_next)
    end

    def word_break(cp : UInt32, p : UInt32, nxt : UInt8, has_next : Bool) : Bool
      cur = UW::Props.wb(p)
      a   = @raw_prev

      ignorable = false

      if !@has_prev
        brk = true
      elsif a == WB_CR && cur == WB_LF
        brk = false
      elsif a == WB_NEWLINE || a == WB_CR || a == WB_LF
        brk = true
      elsif cur == WB_NEWLINE || cur == WB_CR || cur == WB_LF
        brk = true
      elsif a == WB_ZWJ && UW::Props.pict?(p)
        brk = false
      elsif a == WB_WSEGSP && cur == WB_WSEGSP
        brk = false
      elsif cur == WB_EXTEND || cur == WB_FORMAT || cur == WB_ZWJ
        brk       = false
        ignorable = true
      else
        brk = core(cur, nxt, has_next)
      end

      @raw_prev = cur
      @has_prev = true

      unless ignorable
        @sig2     = @sig1
        @has_sig2 = @has_sig1
        @sig1     = cur
        @has_sig1 = true
        if cur == WB_RI
          @ri_run += 1
        else
          @ri_run = 0
        end
      end

      brk
    end

    @[AlwaysInline]
    private def ah?(x : UInt8) : Bool
      x == WB_ALETTER || x == WB_HEBREW
    end

    @[AlwaysInline]
    private def midnumletq?(x : UInt8) : Bool
      x == WB_MIDNUMLET || x == WB_SQUOTE
    end

    private def core(cur : UInt8, nxt : UInt8, has_next : Bool) : Bool
      return true unless @has_sig1
      pv  = @sig1
      pv2 = @sig2

      return false if ah?(pv) && ah?(cur)
      return false if ah?(pv) && (cur == WB_MIDLET || midnumletq?(cur)) && has_next && ah?(nxt)
      return false if @has_sig2 && ah?(pv2) && (pv == WB_MIDLET || midnumletq?(pv)) && ah?(cur)
      return false if pv == WB_HEBREW && cur == WB_SQUOTE
      return false if pv == WB_HEBREW && cur == WB_DQUOTE && has_next && nxt == WB_HEBREW
      return false if @has_sig2 && pv2 == WB_HEBREW && pv == WB_DQUOTE && cur == WB_HEBREW
      return false if pv == WB_NUMERIC && cur == WB_NUMERIC
      return false if ah?(pv) && cur == WB_NUMERIC
      return false if pv == WB_NUMERIC && ah?(cur)
      return false if @has_sig2 && pv2 == WB_NUMERIC && (pv == WB_MIDNUM || midnumletq?(pv)) && cur == WB_NUMERIC
      return false if pv == WB_NUMERIC && (cur == WB_MIDNUM || midnumletq?(cur)) && has_next && nxt == WB_NUMERIC
      return false if pv == WB_KATAKANA && cur == WB_KATAKANA
      return false if (ah?(pv) || pv == WB_NUMERIC || pv == WB_KATAKANA || pv == WB_EXTNUM) && cur == WB_EXTNUM
      return false if pv == WB_EXTNUM && (ah?(cur) || cur == WB_NUMERIC || cur == WB_KATAKANA)
      return false if cur == WB_RI && (@ri_run & 1) == 1
      true
    end
  end

  struct Utf32Words
    def initialize(@cps : Slice(UInt32), @opts : WidthOpts = WidthOpts.unicode)
      @ptr       = @cps.to_unsafe
      @n         = @cps.size
      @i         = 0
      @st        = WordState.new
      @have_seed = false
      @seed_cp   = 0_u32
      @seed_p    = 0_u32
    end

    def reset(cps : Slice(UInt32), opts : WidthOpts = @opts) : Nil
      @cps       = cps
      @opts      = opts
      @ptr       = cps.to_unsafe
      @n         = cps.size
      @i         = 0
      @st.reset
      @have_seed = false
      @seed_cp   = 0_u32
      @seed_p    = 0_u32
    end

    private def peek_sig(from : Int32) : {UInt8, Bool}
      j = from
      while j < @n
        c = UW::Props.wb(UW::Props.props(@ptr[j]))
        return {c, true} unless c == WB_EXTEND || c == WB_FORMAT || c == WB_ZWJ
        j += 1
      end
      {WB_OTHER, false}
    end

    def next? : WordSpan?
      return nil if @i >= @n && !@have_seed

      start    = @i
      consumed = 0

      if @have_seed
        start = @i - 1
        consumed += 1
        @have_seed = false
      end

      while @i < @n
        cp        = @ptr[@i]
        p         = UW::Props.props(cp)
        nxt, hasn = peek_sig(@i + 1)
        if @st.word_break(cp, p, nxt, hasn) && consumed > 0
          @seed_cp   = cp
          @seed_p    = p
          @have_seed = true
          @i += 1
          return WordSpan.new(UW.swidth(@cps[start, consumed], CtrlPolicy::Skip, @opts), consumed)
        end
        consumed += 1
        @i += 1
      end

      return nil if consumed == 0
      WordSpan.new(UW.swidth(@cps[start, consumed], CtrlPolicy::Skip, @opts), consumed)
    end

    def each(& : WordSpan ->) : Nil
      while span = next?
        yield span
      end
    end
  end

  struct Utf8Words
    def initialize(@bytes : Bytes, @policy : Utf8Policy = Utf8Policy::Replace, @opts : WidthOpts = WidthOpts.unicode)
      @ptr       = @bytes.to_unsafe
      @n         = @bytes.size
      @i         = 0
      @st        = WordState.new
      @have_seed = false
      @seed_len  = 0
    end

    def reset(bytes : Bytes, policy : Utf8Policy = @policy, opts : WidthOpts = @opts) : Nil
      @bytes     = bytes
      @policy    = policy
      @opts      = opts
      @ptr       = bytes.to_unsafe
      @n         = bytes.size
      @i         = 0
      @st.reset
      @have_seed = false
      @seed_len  = 0
    end

    def reset(s : String, policy : Utf8Policy = @policy, opts : WidthOpts = @opts) : Nil
      reset(s.to_slice, policy, opts)
    end

    private def peek_sig(from : Int32) : {UInt8, Bool}
      j = from
      while j < @n
        cp, len, bad = UW.utf8_decode(@ptr + j, @n - j)
        return {WB_OTHER, false} if bad && @policy.strict?
        c = UW::Props.wb(UW::Props.props(cp))
        return {c, true} unless c == WB_EXTEND || c == WB_FORMAT || c == WB_ZWJ
        j += len
      end
      {WB_OTHER, false}
    end

    def next? : WordSpan?
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
        p         = UW::Props.props(cp)
        nxt, hasn = peek_sig(@i + len)
        if @st.word_break(cp, p, nxt, hasn) && consumed > 0
          @seed_len  = len
          @have_seed = true
          @i += len
          return WordSpan.new(UW.swidth(@bytes[start, consumed], @policy, CtrlPolicy::Skip, @opts), consumed)
        end
        consumed += len
        @i += len
      end

      return nil if consumed == 0
      WordSpan.new(UW.swidth(@bytes[start, consumed], @policy, CtrlPolicy::Skip, @opts), consumed)
    end

    def each(& : WordSpan ->) : Nil
      while span = next?
        yield span
      end
    end
  end
end
