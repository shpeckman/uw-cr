# src/uw/tables.cr

module UW
  UNICODE_VERSION = "17.0.0"

  BLOCK_BITS  =    8
  BLOCK_SIZE  =  256
  STAGE1_LEN  = 4352
  N_BLOCKS    =  123
  GCB_CLASSES =   14

  private STAGE1_BLOB = {{ read_file("#{__DIR__}/stage1.bin") }}
  private STAGE2_BLOB = {{ read_file("#{__DIR__}/stage2.bin") }}
  private BREAK_BLOB  = {{ read_file("#{__DIR__}/break.bin") }}

  private def self.load_u16(blob : String, count : Int32) : Slice(UInt16)
    out = Slice(UInt16).new(count)
    src = blob.to_slice
    i   = 0
    while i < count
      out.to_unsafe[i] = IO::ByteFormat::LittleEndian.decode(UInt16, src[i * 2, 2])
      i += 1
    end
    out
  end

  STAGE1      = load_u16(STAGE1_BLOB, STAGE1_LEN)
  STAGE2      = load_u16(STAGE2_BLOB, N_BLOCKS * BLOCK_SIZE)
  BREAK_TABLE = BREAK_BLOB.to_slice
end
