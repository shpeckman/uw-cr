# src/uw/iter.cr

module UW
  record Span, width : Int32, size : Int32, kind : SpanKind = SpanKind::Graphemic

  struct Utf32Clusters
    def initialize(@cps : Slice(UInt32), @opts : WidthOpts = WidthOpts.unicode)
      @ptr       = @cps.to_unsafe
      @n         = @cps.size
      @i         = 0
      @char_i    = 0
      @st        = State.new
      @cl        = Cluster.new(@opts.cap, @opts.mode, @opts.ambiguous_wide)
      @have_seed = false
      @seed_cp   = 0_u32
      @seed_p    = 0_u32
    end

    def reset(cps : Slice(UInt32), opts : WidthOpts = @opts) : Nil
      @cps    = cps
      @opts   = opts
      @ptr    = cps.to_unsafe
      @n      = cps.size
      @i      = 0
      @char_i = 0
      @st.reset
      @cl.configure(opts.cap, opts.mode, opts.ambiguous_wide)
      @cl.reset
      @have_seed = false
      @seed_cp   = 0_u32
      @seed_p    = 0_u32
    end

    def next? : Span?
      return nil if @i >= @n && !@have_seed

      @cl.reset
      start_char = @char_i
      consumed   = 0

      if @have_seed
        @cl.push(@seed_cp, @seed_p)
        consumed += 1
        @char_i += 1
        @have_seed = false
      end

      while @i < @n
        cp = @ptr[@i]
        p  = Props.props(cp)
        if @st.grapheme_break(cp, p) && @cl.started
          @seed_cp   = cp
          @seed_p    = p
          @have_seed = true
          @i += 1
          return Span.new(@cl.display_width, consumed, @cl.kind)
        end
        @cl.push(cp, p)
        consumed += 1
        @char_i += 1
        @i += 1
      end

      return nil if consumed == 0
      Span.new(@cl.display_width, consumed, @cl.kind)
    end

    def each(& : Span ->) : Nil
      while span = next?
        yield span
      end
    end
  end

  struct Utf8Clusters
    def initialize(@bytes : Bytes, @policy : Utf8Policy = Utf8Policy::Replace, @opts : WidthOpts = WidthOpts.unicode)
      @ptr       = @bytes.to_unsafe
      @n         = @bytes.size
      @i         = 0
      @st        = State.new
      @cl        = Cluster.new(@opts.cap, @opts.mode, @opts.ambiguous_wide)
      @have_seed = false
      @seed_cp   = 0_u32
      @seed_p    = 0_u32
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
      @cl.configure(opts.cap, opts.mode, opts.ambiguous_wide)
      @cl.reset
      @have_seed = false
      @seed_cp   = 0_u32
      @seed_p    = 0_u32
      @seed_len  = 0
    end

    def reset(s : String, policy : Utf8Policy = @policy, opts : WidthOpts = @opts) : Nil
      reset(s.to_slice, policy, opts)
    end

    def next? : Span?
      return nil if @i >= @n && !@have_seed

      @cl.reset
      consumed = 0

      if @have_seed
        @cl.push(@seed_cp, @seed_p)
        consumed += @seed_len
        @have_seed = false
      end

      while @i < @n
        cp, len, bad = UW.utf8_decode(@ptr + @i, @n - @i)
        break if bad && @policy.strict?
        p = Props.props(cp)
        if @st.grapheme_break(cp, p) && @cl.started
          @seed_cp   = cp
          @seed_p    = p
          @seed_len  = len
          @have_seed = true
          @i += len
          return Span.new(@cl.display_width, consumed, @cl.kind)
        end
        @cl.push(cp, p)
        consumed += len
        @i += len
      end

      return nil if consumed == 0
      Span.new(@cl.display_width, consumed, @cl.kind)
    end

    def each(& : Span ->) : Nil
      while span = next?
        yield span
      end
    end
  end
end