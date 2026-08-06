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

  private WB_OTHER     =  0_u8
  private WB_CR        =  1_u8
  private WB_LF        =  2_u8
  private WB_NEWLINE   =  3_u8
  private WB_EXTEND    =  4_u8
  private WB_ZWJ       =  5_u8
  private WB_FORMAT    =  6_u8
  private WB_RI        =  7_u8
  private WB_WSEGSP    =  8_u8
  private WB_ALETTER   =  9_u8
  private WB_HEBREW    = 10_u8
  private WB_KATAKANA  = 11_u8
  private WB_NUMERIC   = 12_u8
  private WB_EXTNUM    = 13_u8
  private WB_MIDLET    = 14_u8
  private WB_MIDNUM    = 15_u8
  private WB_MIDNUMLET = 16_u8
  private WB_SQUOTE    = 17_u8
  private WB_DQUOTE    = 18_u8

  private LB_AL  =  0_u8
  private LB_BK  =  1_u8
  private LB_CR  =  2_u8
  private LB_LF  =  3_u8
  private LB_NL  =  4_u8
  private LB_SP  =  5_u8
  private LB_ZW  =  6_u8
  private LB_ZWJ =  7_u8
  private LB_CM  =  8_u8
  private LB_WJ  =  9_u8
  private LB_GL  = 10_u8
  private LB_CL  = 11_u8
  private LB_CP  = 12_u8
  private LB_EX  = 13_u8
  private LB_IS  = 14_u8
  private LB_SY  = 15_u8
  private LB_OP  = 16_u8
  private LB_QU  = 17_u8
  private LB_NS  = 18_u8
  private LB_B2  = 19_u8
  private LB_HY  = 20_u8
  private LB_HH  = 21_u8
  private LB_BA  = 22_u8
  private LB_BB  = 23_u8
  private LB_NU  = 24_u8
  private LB_PR  = 25_u8
  private LB_PO  = 26_u8
  private LB_ID  = 27_u8
  private LB_IN  = 28_u8
  private LB_EB  = 29_u8
  private LB_EM  = 30_u8
  private LB_H2  = 31_u8
  private LB_H3  = 32_u8
  private LB_JL  = 33_u8
  private LB_JV  = 34_u8
  private LB_JT  = 35_u8
  private LB_HL  = 36_u8
  private LB_RI  = 37_u8
  private LB_CB  = 38_u8
  private LB_AK  = 39_u8
  private LB_AP  = 40_u8
  private LB_AS  = 41_u8
  private LB_VF  = 42_u8
  private LB_VI  = 43_u8
  private LB_SOT = 44_u8
  private LB_EOT = 45_u8

  module Props
    @[AlwaysInline]
    protected def self.props(cp : UInt32) : UInt32
      return 0_u32 if cp >= (STAGE1_LEN.to_u32 << BLOCK_BITS)
      STAGE2.to_unsafe[STAGE1.to_unsafe[cp >> BLOCK_BITS].to_i32 * BLOCK_SIZE + (cp & (BLOCK_SIZE - 1)).to_i32]
    end

    @[AlwaysInline]
    protected def self.width(p : UInt32) : Int32
      (p & 0x3).to_i32
    end

    @[AlwaysInline]
    protected def self.legacy_width(p : UInt32) : Int32
      w = (p & 0x3).to_i32
      w == 3 ? -1 : w
    end

    @[AlwaysInline]
    protected def self.gcb(p : UInt32) : UInt8
      ((p >> 2) & 0xF).to_u8
    end

    @[AlwaysInline]
    protected def self.pict?(p : UInt32) : Bool
      (p & 0x40) != 0
    end

    @[AlwaysInline]
    protected def self.epres?(p : UInt32) : Bool
      (p & 0x80) != 0
    end

    @[AlwaysInline]
    protected def self.incb(p : UInt32) : Int32
      ((p >> 8) & 0x3).to_i32
    end

    @[AlwaysInline]
    protected def self.wb(p : UInt32) : UInt8
      ((p >> 10) & 0x1F).to_u8
    end

    @[AlwaysInline]
    protected def self.lb(p : UInt32) : UInt8
      ((p >> 15) & 0x3F).to_u8
    end

    @[AlwaysInline]
    protected def self.pi?(p : UInt32) : Bool
      (p & (1_u32 << 21)) != 0
    end

    @[AlwaysInline]
    protected def self.pf?(p : UInt32) : Bool
      (p & (1_u32 << 22)) != 0
    end

    @[AlwaysInline]
    protected def self.east_asian?(p : UInt32) : Bool
      (p & (1_u32 << 23)) != 0
    end

    @[AlwaysInline]
    protected def self.pict_unassigned?(p : UInt32) : Bool
      (p & (1_u32 << 24)) != 0
    end

    @[AlwaysInline]
    protected def self.dotted_circle?(p : UInt32) : Bool
      (p & (1_u32 << 25)) != 0
    end
  end
end
