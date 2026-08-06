# tools/lib_setup.cr

require "http/client"
require "file_utils"
require "bit_array"

module LibSetup
  UCD_VERSION = "17.0.0"
  BASE_URL    = "https://www.unicode.org/Public/#{UCD_VERSION}/ucd"
  CACHE_DIR   = "#{__DIR__}/ucd"
  OUT_DIR     = "#{__DIR__}/../src/uw"
  SPEC_DIR    = "#{__DIR__}/../spec/data"

  TEST_BASE_URL = "#{BASE_URL}/auxiliary"
  TEST_FILES    = {
    "GraphemeBreakTest.txt",
    "WordBreakTest.txt",
    "SentenceBreakTest.txt",
    "LineBreakTest.txt",
  }

  MAX        = 0x110000
  BLOCK_SIZE =      256

  SOURCES = {
    "UnicodeData.txt"           => "UnicodeData.txt",
    "EastAsianWidth.txt"        => "EastAsianWidth.txt",
    "DerivedCoreProperties.txt" => "DerivedCoreProperties.txt",
    "GraphemeBreakProperty.txt" => "auxiliary/GraphemeBreakProperty.txt",
    "WordBreakProperty.txt"     => "auxiliary/WordBreakProperty.txt",
    "SentenceBreakProperty.txt" => "auxiliary/SentenceBreakProperty.txt",
    "DerivedLineBreak.txt"      => "extracted/DerivedLineBreak.txt",
    "PropertyValueAliases.txt"  => "PropertyValueAliases.txt",
    "emoji-data.txt"            => "emoji/emoji-data.txt",
  }

  GCB_CODE = {
    "CR" => 1, "LF" => 2, "Control" => 3, "Extend" => 4, "ZWJ" => 5,
    "Prepend" => 6, "SpacingMark" => 7, "L" => 8, "V" => 9, "T" => 10,
    "LV" => 11, "LVT" => 12, "Regional_Indicator" => 13,
  }

  INCB_CODE = {"Consonant" => 1, "Extend" => 2, "Linker" => 3}

  ZERO_WIDTH_GCB = {"Extend", "ZWJ", "Prepend", "SpacingMark"}

  WB_CODE = {
    "CR" => 1, "LF" => 2, "Newline" => 3, "Extend" => 4, "ZWJ" => 5,
    "Format" => 6, "Regional_Indicator" => 7, "WSegSpace" => 8,
    "ALetter" => 9, "Hebrew_Letter" => 10, "Katakana" => 11, "Numeric" => 12,
    "ExtendNumLet" => 13, "MidLetter" => 14, "MidNum" => 15, "MidNumLet" => 16,
    "Single_Quote" => 17, "Double_Quote" => 18,
  }
  WB_N = 19

  SB_CODE = {
    "CR" => 1, "LF" => 2, "Extend" => 3, "Sep" => 4, "Format" => 5,
    "Sp" => 6, "Lower" => 7, "Upper" => 8, "OLetter" => 9, "Numeric" => 10,
    "ATerm" => 11, "SContinue" => 12, "STerm" => 13, "Close" => 14,
  }
  SB_N = 15

  LB_CODE = {
    "AL" => 0, "BK" => 1, "CR" => 2, "LF" => 3, "NL" => 4, "SP" => 5,
    "ZW" => 6, "ZWJ" => 7, "CM" => 8, "WJ" => 9, "GL" => 10, "CL" => 11,
    "CP" => 12, "EX" => 13, "IS" => 14, "SY" => 15, "OP" => 16, "QU" => 17,
    "NS" => 18, "B2" => 19, "HY" => 20, "HH" => 21, "BA" => 22, "BB" => 23,
    "NU" => 24, "PR" => 25, "PO" => 26, "ID" => 27, "IN" => 28, "EB" => 29,
    "EM" => 30, "H2" => 31, "H3" => 32, "JL" => 33, "JV" => 34, "JT" => 35,
    "HL" => 36, "RI" => 37, "CB" => 38, "AK" => 39, "AP" => 40, "AS" => 41,
    "VF" => 42, "VI" => 43,
  }
  LB_N = 44

  DOTTED_CIRCLE = 0x25CC

  def self.fetch(refresh : Bool)
    FileUtils.mkdir_p(CACHE_DIR)
    SOURCES.each do |local, remote|
      path = "#{CACHE_DIR}/#{local}"
      next if File.exists?(path) && !refresh
      url = "#{BASE_URL}/#{remote}"
      STDERR.puts "fetching #{url}"
      body = HTTP::Client.get(url) do |resp|
        raise "GET #{url} -> #{resp.status_code}" unless resp.success?
        resp.body_io.gets_to_end
      end
      File.write(path, body)
    end
  end

  def self.each_range(local : String, &)
    File.each_line("#{CACHE_DIR}/#{local}") do |raw|
      line = raw
      if h = line.index('#')
        line = line[0...h]
      end
      line = line.strip
      next if line.empty?
      cols = line.split(';').map(&.strip)
      rng  = cols[0]
      if dots = rng.index("..")
        lo = rng[0...dots].to_i(16)
        hi = rng[(dots + 2)..].to_i(16)
      else
        lo = hi = rng.to_i(16)
      end
      hi = MAX - 1 if hi >= MAX
      yield lo, hi, cols
    end
  end

  def self.build_props : Array(UInt32)
    gc      = Array(String?).new(MAX, nil)
    gbp     = Array(String?).new(MAX, nil)
    wbp     = Array(String?).new(MAX, nil)
    sbp     = Array(String?).new(MAX, nil)
    lbp     = Array(String?).new(MAX, nil)
    eaw     = Array(String).new(MAX, "N")
    incb    = Array(String?).new(MAX, nil)
    epres   = BitArray.new(MAX)
    extpict = BitArray.new(MAX)

    pending : {Int32, String}? = nil
    File.each_line("#{CACHE_DIR}/UnicodeData.txt") do |raw|
      f    = raw.chomp.split(';')
      cp   = f[0].to_i(16)
      name = f[1]
      cat  = f[2]
      if name.ends_with?(", First>")
        pending = {cp, cat}
        next
      end
      if name.ends_with?(", Last>") && (p = pending)
        (p[0]..cp).each { |c| gc[c] = p[1] if c < MAX }
        pending = nil
        next
      end
      gc[cp] = cat if cp < MAX
    end

    each_range("EastAsianWidth.txt") do |lo, hi, cols|
      v = cols[1]
      (lo..hi).each { |cp| eaw[cp] = v }
    end

    each_range("GraphemeBreakProperty.txt") do |lo, hi, cols|
      v = cols[1]
      (lo..hi).each { |cp| gbp[cp] = v }
    end

    each_range("WordBreakProperty.txt") do |lo, hi, cols|
      v = cols[1]
      (lo..hi).each { |cp| wbp[cp] = v }
    end

    each_range("SentenceBreakProperty.txt") do |lo, hi, cols|
      v = cols[1]
      (lo..hi).each { |cp| sbp[cp] = v }
    end

    each_range("DerivedLineBreak.txt") do |lo, hi, cols|
      v = cols[1]
      (lo..hi).each { |cp| lbp[cp] = v }
    end

    each_range("emoji-data.txt") do |lo, hi, cols|
      case cols[1]
      when "Emoji_Presentation"    then (lo..hi).each { |cp| epres[cp] = true }
      when "Extended_Pictographic" then (lo..hi).each { |cp| extpict[cp] = true }
      end
    end

    each_range("DerivedCoreProperties.txt") do |lo, hi, cols|
      next unless cols[1] == "InCB"
      v = cols[2]
      (lo..hi).each { |cp| incb[cp] = v }
    end

    lb_alias = {} of String => String
    File.each_line("#{CACHE_DIR}/PropertyValueAliases.txt") do |raw|
      line = raw
      if h = line.index('#')
        line = line[0...h]
      end
      line = line.strip
      next if line.empty?
      f = line.split(';').map(&.strip)
      next unless f.size >= 2 && f[0] == "lb"
      short = f[1]
      i     = 1
      while i < f.size
        lb_alias[f[i]] = short
        i += 1
      end
    end

    lb_default = Array(String).new(MAX, "XX")
    File.each_line("#{CACHE_DIR}/DerivedLineBreak.txt") do |raw|
      line = raw.strip
      next unless line.starts_with?("# @missing:")
      body = line[11..].strip
      f    = body.split(';').map(&.strip)
      next if f.size < 2
      rng = f[0]
      v   = lb_alias[f[1]]? || "XX"
      if dots = rng.index("..")
        lo = rng[0...dots].to_i(16)
        hi = rng[(dots + 2)..].to_i(16)
      else
        lo = hi = rng.to_i(16)
      end
      hi = MAX - 1 if hi >= MAX
      (lo..hi).each { |cp| lb_default[cp] = v }
    end

    props = Array(UInt32).new(MAX, 0_u32)
    cp    = 0
    while cp < MAX
      cat = gc[cp]
      g   = gbp[cp]
      ea  = eaw[cp]

      w =
        if cat == "Cc"
          3
        elsif g == "Regional_Indicator"
          1
        elsif (g && ZERO_WIDTH_GCB.includes?(g)) || cat == "Cf"
          0
        elsif ea == "W" || ea == "F" || epres[cp]
          2
        else
          1
        end

      raw_lb = lbp[cp] || lb_default[cp]
      lb =
        case raw_lb
        when "AI", "SG", "XX" then "AL"
        when "CJ"             then "NS"
        when "SA"             then (cat == "Mn" || cat == "Mc") ? "CM" : "AL"
        else                       raw_lb
        end

      wb = wbp[cp]
      sb = sbp[cp]

      packed = w.to_u32
      packed |= ((g ? (GCB_CODE[g]? || 0) : 0) << 2).to_u32
      packed |= 0x40_u32 if extpict[cp]
      packed |= 0x80_u32 if epres[cp]
      if iv = incb[cp]
        packed |= ((INCB_CODE[iv]? || 0) << 8).to_u32
      end
      packed |= ((wb ? (WB_CODE[wb]? || 0) : 0).to_u32 << 10)
      packed |= ((LB_CODE[lb]? || 0).to_u32 << 15)
      packed |= (1_u32 << 21) if cat == "Pi"
      packed |= (1_u32 << 22) if cat == "Pf"
      packed |= (1_u32 << 23) if ea == "F" || ea == "W" || ea == "H"
      packed |= (1_u32 << 24) if extpict[cp] && cat.nil?
      packed |= (1_u32 << 25) if cp == DOTTED_CIRCLE
      packed |= ((sb ? (SB_CODE[sb]? || 0) : 0).to_u32 << 26)
      packed |= (1_u32 << 30) if ea == "A"

      props[cp] = packed
      cp += 1
    end
    props
  end

  def self.build_trie(props : Array(UInt32)) : {Array(UInt16), Array(UInt32)}
    n_blocks = MAX // BLOCK_SIZE
    index    = {} of Array(UInt32) => UInt16
    blocks   = [] of Array(UInt32)
    stage1   = Array(UInt16).new(n_blocks)

    b = 0
    while b < n_blocks
      block = props[(b * BLOCK_SIZE), BLOCK_SIZE]
      idx   = index[block]?
      unless idx
        idx = blocks.size.to_u16
        index[block] = idx
        blocks << block
      end
      stage1 << idx
      b += 1
    end

    stage2 = Array(UInt32).new(blocks.size * BLOCK_SIZE)
    blocks.each { |blk| blk.each { |v| stage2 << v } }
    {stage1, stage2}
  end

  BRK     = 0_u8
  NOBRK   = 1_u8
  CONSULT = 2_u8
  GCB_N   =   14

  C_OTHER       =  0
  C_CR          =  1
  C_LF          =  2
  C_CONTROL     =  3
  C_EXTEND      =  4
  C_ZWJ         =  5
  C_PREPEND     =  6
  C_SPACINGMARK =  7
  C_L           =  8
  C_V           =  9
  C_T           = 10
  C_LV          = 11
  C_LVT         = 12
  C_RI          = 13

  def self.build_break_table : Array(UInt8)
    tbl = Array(UInt8).new(GCB_N * GCB_N, BRK)
    a   = 0
    while a < GCB_N
      b = 0
      while b < GCB_N
        tbl[a * GCB_N + b] =
          if a == C_CR && b == C_LF
            NOBRK
          elsif a == C_CONTROL || a == C_CR || a == C_LF
            BRK
          elsif b == C_CONTROL || b == C_CR || b == C_LF
            BRK
          elsif a == C_L && (b == C_L || b == C_V || b == C_LV || b == C_LVT)
            NOBRK
          elsif (a == C_LV || a == C_V) && (b == C_V || b == C_T)
            NOBRK
          elsif (a == C_LVT || a == C_T) && b == C_T
            NOBRK
          elsif b == C_EXTEND || b == C_ZWJ
            NOBRK
          elsif b == C_SPACINGMARK
            NOBRK
          elsif a == C_PREPEND
            NOBRK
          elsif a == C_RI && b == C_RI
            CONSULT
          elsif b == C_OTHER
            CONSULT
          else
            BRK
          end
        b += 1
      end
      a += 1
    end
    tbl
  end

  def self.write_u16(path : String, data : Array(UInt16))
    bytes = Bytes.new(data.size * 2)
    data.each_with_index do |v, i|
      IO::ByteFormat::LittleEndian.encode(v, bytes[i * 2, 2])
    end
    File.write(path, bytes)
  end

  def self.write_u32(path : String, data : Array(UInt32))
    bytes = Bytes.new(data.size * 4)
    data.each_with_index do |v, i|
      IO::ByteFormat::LittleEndian.encode(v, bytes[i * 4, 4])
    end
    File.write(path, bytes)
  end

  def self.clean
    STDERR.puts "cleaning generated artifacts"
    FileUtils.rm_rf(CACHE_DIR)
    Dir.glob("#{OUT_DIR}/*.bin").each { |f| File.delete(f) }
    if Dir.exists?(SPEC_DIR)
      Dir.glob("#{SPEC_DIR}/*").each { |f| File.delete(f) if File.file?(f) }
    end
  end

  def self.fetch_tests(refresh : Bool)
    FileUtils.mkdir_p(SPEC_DIR)
    TEST_FILES.each do |name|
      path = "#{SPEC_DIR}/#{name}"
      next if File.exists?(path) && !refresh
      url = "#{TEST_BASE_URL}/#{name}"
      STDERR.puts "fetching #{url}"
      body = HTTP::Client.get(url) do |resp|
        raise "GET #{url} -> #{resp.status_code}" unless resp.success?
        resp.body_io.gets_to_end
      end
      File.write(path, body)
    end
  end

  def self.run
    if ARGV.includes?("--clean-only")
      clean
      STDERR.puts "clean complete"
      return
    end

    refresh = ARGV.includes?("--refresh")
    clean if refresh
    fetch(refresh)

    STDERR.puts "building packed properties for #{MAX} code points"
    props = build_props

    stage1, stage2 = build_trie(props)
    STDERR.puts "stage1: #{stage1.size} entries, stage2: #{stage2.size // BLOCK_SIZE} blocks"

    brk_table = build_break_table

    FileUtils.mkdir_p(OUT_DIR)
    write_u16("#{OUT_DIR}/stage1.bin", stage1)
    write_u32("#{OUT_DIR}/stage2.bin", stage2)
    File.write("#{OUT_DIR}/break.bin", Bytes.new(brk_table.size) { |i| brk_table[i] })

    tables_src = <<-CR
    # src/uw/tables.cr

    module UW
      UNICODE_VERSION = #{UCD_VERSION.inspect}

      BLOCK_BITS = 8
      BLOCK_SIZE = #{BLOCK_SIZE}
      STAGE1_LEN = #{stage1.size}
      N_BLOCKS   = #{stage2.size // BLOCK_SIZE}
      GCB_CLASSES = #{GCB_N}
      WB_CLASSES = #{WB_N}
      SB_CLASSES = #{SB_N}
      LB_CLASSES = #{LB_N}

      private STAGE1_BLOB = {{ read_file("\#{__DIR__}/stage1.bin") }}
      private STAGE2_BLOB = {{ read_file("\#{__DIR__}/stage2.bin") }}
      private BREAK_BLOB  = {{ read_file("\#{__DIR__}/break.bin") }}

      private def self.load_u16(blob : String, count : Int32) : Slice(UInt16)
        out = Slice(UInt16).new(count)
        src = blob.to_slice
        i = 0
        while i < count
          out.to_unsafe[i] = IO::ByteFormat::LittleEndian.decode(UInt16, src[i * 2, 2])
          i += 1
        end
        out
      end

      private def self.load_u32(blob : String, count : Int32) : Slice(UInt32)
        out = Slice(UInt32).new(count)
        src = blob.to_slice
        i = 0
        while i < count
          out.to_unsafe[i] = IO::ByteFormat::LittleEndian.decode(UInt32, src[i * 4, 4])
          i += 1
        end
        out
      end

      STAGE1 = load_u16(STAGE1_BLOB, STAGE1_LEN)
      STAGE2 = load_u32(STAGE2_BLOB, N_BLOCKS * BLOCK_SIZE)
      BREAK_TABLE = BREAK_BLOB.to_slice
    end
    CR
    File.write("#{OUT_DIR}/tables.cr", tables_src + "\n")

    STDERR.puts "wrote #{OUT_DIR}/stage1.bin, #{OUT_DIR}/stage2.bin, #{OUT_DIR}/break.bin, #{OUT_DIR}/tables.cr"

    fetch_tests(refresh)

    STDERR.puts "setup complete"
  end
end

LibSetup.run