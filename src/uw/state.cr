# src/uw/state.cr

module UW
  struct State
    def initialize
      @prev_gcb         = GCB_OTHER
      @ri_parity        = 0_u8
      @saw_pict         = false
      @zwj_after_pict   = false
      @incb_consonant   = false
      @incb_linker_seen = false
      @has_prev         = false
    end

    def reset : Nil
      @prev_gcb         = GCB_OTHER
      @ri_parity        = 0_u8
      @saw_pict         = false
      @zwj_after_pict   = false
      @incb_consonant   = false
      @incb_linker_seen = false
      @has_prev         = false
    end

    def grapheme_break(cp : UInt32) : Bool
      grapheme_break(cp, UW::Props.props(cp))
    end

    def grapheme_break(cp : UInt32, p : UInt16) : Bool
      gcb  = UW::Props.gcb(p)
      pict = UW::Props.pict?(p)
      incb = UW::Props.incb(p)

      if !@has_prev
        brk = true
      else
        a        = @prev_gcb
        decision = UW::BREAK_TABLE.to_unsafe[a.to_i32 * GCB_CLASSES + gcb.to_i32]
        if decision == 0_u8
          brk = true
        elsif decision == 1_u8
          brk = false
        elsif incb == INCB_CONSONANT && @incb_consonant && @incb_linker_seen
          brk = false
        elsif @zwj_after_pict && pict
          brk = false
        elsif gcb == GCB_RI && (@ri_parity & 1) != 0
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
        @saw_pict       = true
        @zwj_after_pict = false
      elsif gcb == GCB_EXTEND
        @zwj_after_pict = false
      elsif gcb == GCB_ZWJ
        @zwj_after_pict = @saw_pict
      else
        @saw_pict       = false
        @zwj_after_pict = false
      end

      if incb == INCB_CONSONANT
        @incb_consonant   = true
        @incb_linker_seen = false
      elsif incb == INCB_LINKER
        @incb_linker_seen = true if @incb_consonant
      elsif incb == INCB_EXTEND
      else
        @incb_consonant   = false
        @incb_linker_seen = false
      end

      @prev_gcb = gcb
      @has_prev = true
      brk
    end
  end
end
