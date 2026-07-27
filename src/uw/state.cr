# src/uw/state.cr

module UW
  struct State
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
      p = UW::Props.props(cp)
      gcb = UW::Props.gcb(p)
      pict = UW::Props.pict?(p)
      incb = UW::Props.incb(p)

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
      else
        @incb_consonant = false
        @incb_linker_seen = false
      end

      @prev_gcb = gcb
      @has_prev = true
      brk
    end
  end
end