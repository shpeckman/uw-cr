# src/uw/props.cr

module UW
  private VS15 = 0xFE0E_u32
  private VS16 = 0xFE0F_u32

  private GCB_OTHER       =  0_u8
  private GCB_CR          =  1_u8
  private GCB_LF          =  2_u8
  private GCB_CONTROL     =  3_u8
  private GCB_EXTEND      =  4_u8
  private GCB_ZWJ         =  5_u8
  private GCB_PREPEND     =  6_u8
  private GCB_SPACINGMARK =  7_u8
  private GCB_L           =  8_u8
  private GCB_V           =  9_u8
  private GCB_T           = 10_u8
  private GCB_LV          = 11_u8
  private GCB_LVT         = 12_u8
  private GCB_RI          = 13_u8

  private INCB_NONE      = 0
  private INCB_CONSONANT = 1
  private INCB_EXTEND    = 2
  private INCB_LINKER    = 3

  # Low-level packed-property accessors, protected so only the types in this
  # module can reach them. Not part of the public API.
  module Props
    @[AlwaysInline]
    protected def self.props(cp : UInt32) : UInt16
      return 0_u16 if cp >= (STAGE1_LEN.to_u32 << BLOCK_BITS)
      STAGE2[STAGE1.to_unsafe[cp >> BLOCK_BITS].to_i32 * BLOCK_SIZE + (cp & (BLOCK_SIZE - 1)).to_i32]
    end

    @[AlwaysInline]
    protected def self.width(p : UInt16) : Int32
      (p & 0x3).to_i32
    end

    @[AlwaysInline]
    protected def self.gcb(p : UInt16) : UInt8
      ((p >> 2) & 0xF).to_u8
    end

    @[AlwaysInline]
    protected def self.pict?(p : UInt16) : Bool
      (p & 0x40) != 0
    end

    @[AlwaysInline]
    protected def self.epres?(p : UInt16) : Bool
      (p & 0x80) != 0
    end

    @[AlwaysInline]
    protected def self.incb(p : UInt16) : Int32
      ((p >> 8) & 0x3).to_i32
    end
  end
end