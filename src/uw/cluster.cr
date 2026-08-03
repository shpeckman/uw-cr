# src/uw/cluster.cr

module UW
  enum SpanKind
    Graphemic = 0
    Control   = 1
    CR        = 2
    LF        = 3
    CRLF      = 4
    Tab       = 5
  end

  struct Cluster
    getter started : Bool
    getter cap     : Int32

    def initialize(@cap : Int32 = CLUSTER_WIDTH_CAP, @mode : WidthMode = WidthMode::Unicode)
      @width             = 0
      @started           = false
      @base_narrow_emoji = false
      @base_width        = 0
      @ri_count          = 0_u8
      @legacy_sum        = 0
      @first_cp          = 0_u32
      @last_cp           = 0_u32
      @count             = 0
    end

    def reset : Nil
      @width             = 0
      @started           = false
      @base_narrow_emoji = false
      @base_width        = 0
      @ri_count          = 0_u8
      @legacy_sum        = 0
      @first_cp          = 0_u32
      @last_cp           = 0_u32
      @count             = 0
    end

    def configure(cap : Int32, mode : WidthMode) : Nil
      @cap  = cap
      @mode = mode
    end

    def push(cp : UInt32) : Nil
      push(cp, UW::Props.props(cp))
    end

    def push(cp : UInt32, p : UInt16) : Nil
      if !@started
        @first_cp = cp
      end
      @last_cp = cp
      @count += 1

      gcb = UW::Props.gcb(p)
      w   = UW::Props.width(p)

      if @mode.legacy?
        lw = UW::Props.legacy_width(p)
        if !@started
          @started    = true
          @legacy_sum = lw < 0 ? -1 : lw
        elsif @legacy_sum >= 0
          @legacy_sum = lw < 0 ? -1 : @legacy_sum + lw
        end
        return
      end

      if gcb == GCB_RI
        @ri_count += 1
        if !@started
          @width   = 1
          @started = true
        end
        @width = 2 if @ri_count == 2
        return
      end

      if cp == VS16
        if @base_narrow_emoji
          @width             = 2
          @base_narrow_emoji = false
        end
        return
      end
      if cp == VS15
        if @base_narrow_emoji
          @width             = @base_width
          @base_narrow_emoji = false
        end
        return
      end

      if !@started
        @started = true
        @width   = (w == 3) ? -1 : w
        if !UW::Props.epres?(p) && w != 2
          @base_narrow_emoji = true
          @base_width        = @width
        end
      elsif @width >= 0 && UW::Props.pict?(p)
        @width += (w == 3) ? 0 : w
        @base_narrow_emoji = false
      end
    end

    def kind : SpanKind
      cp = @first_cp
      return SpanKind::Graphemic if cp >= 0x80_u32 && cp != 0x2028_u32 && cp != 0x2029_u32
      case cp
      when 0x09_u32
        SpanKind::Tab
      when 0x0D_u32
        (@count > 1 && @last_cp == 0x0A_u32) ? SpanKind::CRLF : SpanKind::CR
      when 0x0A_u32, 0x0B_u32, 0x0C_u32, 0x85_u32, 0x2028_u32, 0x2029_u32
        SpanKind::LF
      else
        base = UW::Props.props(cp)
        UW::Props.width(base) == 3 ? SpanKind::Control : SpanKind::Graphemic
      end
    end

    def display_width : Int32
      if @mode.legacy?
        return -1 if @legacy_sum < 0
        return cap_value(@legacy_sum)
      end
      return -1 if @width < 0
      cap_value(@width)
    end

    private def cap_value(w : Int32) : Int32
      if @cap > 0
        w > @cap ? @cap : w
      else
        w
      end
    end
  end
end
