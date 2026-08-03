# tools/gen_tables.cr
#
# Regenerates src/uw/stage1.bin and src/uw/stage2.bin from the raw Unicode
# Character Database. Run: crystal run tools/gen_tables.cr
#
# UCD files are fetched into tools/ucd/ and reused on subsequent runs. Pass
# --refresh to re-download.

require "http/client"
require "file_utils"
require "bit_array"

module Gen
  UCD_VERSION = "17.0.0"
  BASE_URL    = "https://www.unicode.org/Public/#{UCD_VERSION}/ucd"
  CACHE_DIR   = "#{__DIR__}/ucd"
  OUT_DIR     = "#{__DIR__}/../src/uw"

  MAX        = 0x110000
  BLOCK_SIZE =      256

  SOURCES = {
    "UnicodeData.txt"           => "UnicodeData.txt",
    "EastAsianWidth.txt"        => "EastAsianWidth.txt",
    "DerivedCoreProperties.txt" => "DerivedCoreProperties.txt",
    "GraphemeBreakProperty.txt" => "auxiliary/GraphemeBreakProperty.txt",
    "emoji-data.txt"            => "emoji/emoji-data.txt",
  }

  GCB_CODE = {
    "CR" => 1, "LF" => 2, "Control" => 3, "Extend" => 4, "ZWJ" => 5,
    "Prepend" => 6, "SpacingMark" => 7, "L" => 8, "V" => 9, "T" => 10,
    "LV" => 11, "LVT" => 12, "Regional_Indicator" => 13,
  }

  INCB_CODE = {"Consonant" => 1, "Extend" => 2, "Linker" => 3}

  ZERO_WIDTH_GCB = {"Extend", "ZWJ", "Prepend", "SpacingMark"}

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

  # Iterates data lines of a UCD file, yielding {lo, hi, fields} where fields
  # are the semicolon-separated columns after the code-point range.
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

  def self.build_props : Array(UInt16)
    gc      = Array(String?).new(MAX, nil)
    gbp     = Array(String?).new(MAX, nil)
    eaw     = Array(String).new(MAX, "N")
    incb    = Array(String?).new(MAX, nil)
    epres   = BitArray.new(MAX)
    extpict = BitArray.new(MAX)

    # General_Category from UnicodeData.txt, honoring First/Last range rows.
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

    props = Array(UInt16).new(MAX, 0_u16)
    cp    = 0
    while cp < MAX
      cat = gc[cp]
      g   = gbp[cp]

      w =
        if cat == "Cc"
          3
        elsif g == "Regional_Indicator"
          1
        elsif (g && ZERO_WIDTH_GCB.includes?(g)) || cat == "Cf"
          0
        elsif eaw[cp] == "W" || eaw[cp] == "F" || epres[cp]
          2
        else
          1
        end

      packed = w
      packed |= (g ? (GCB_CODE[g]? || 0) : 0) << 2
      packed |= 0x40 if extpict[cp]
      packed |= 0x80 if epres[cp]
      if iv = incb[cp]
        packed |= (INCB_CODE[iv]? || 0) << 8
      end

      props[cp] = packed.to_u16
      cp += 1
    end
    props
  end

  # Two-stage trie: split into 256-entry blocks, deduplicate identical blocks,
  # and record each block's index in stage1.
  def self.build_trie(props : Array(UInt16)) : {Array(UInt16), Array(UInt16)}
    n_blocks = MAX // BLOCK_SIZE
    index    = {} of Array(UInt16) => UInt16
    blocks   = [] of Array(UInt16)
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

    stage2 = Array(UInt16).new(blocks.size * BLOCK_SIZE)
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

  # Encodes the class-only grapheme-break decision for every ordered pair
  # (prev_gcb, cur_gcb). CONSULT marks pairs whose outcome depends on runtime
  # state (GB9c Indic conjunct, GB11 emoji ZWJ, GB12/13 regional indicators);
  # the state machine resolves those. Every other pair is decided here. The
  # rule precedence mirrors UAX #29 exactly.
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

  def self.write_blob(path : String, data : Array(UInt16))
    bytes = Bytes.new(data.size * 2)
    data.each_with_index do |v, i|
      IO::ByteFormat::LittleEndian.encode(v, bytes[i * 2, 2])
    end
    File.write(path, bytes)
  end

  def self.run
    refresh = ARGV.includes?("--refresh")
    fetch(refresh)

    STDERR.puts "building packed properties for #{MAX} code points"
    props = build_props

    stage1, stage2 = build_trie(props)
    STDERR.puts "stage1: #{stage1.size} entries, stage2: #{stage2.size // BLOCK_SIZE} blocks"

    brk_table = build_break_table

    FileUtils.mkdir_p(OUT_DIR)
    write_blob("#{OUT_DIR}/stage1.bin", stage1)
    write_blob("#{OUT_DIR}/stage2.bin", stage2)
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

      STAGE1 = load_u16(STAGE1_BLOB, STAGE1_LEN)
      STAGE2 = load_u16(STAGE2_BLOB, N_BLOCKS * BLOCK_SIZE)
      BREAK_TABLE = BREAK_BLOB.to_slice
    end
    CR
    File.write("#{OUT_DIR}/tables.cr", tables_src + "\n")

    STDERR.puts "wrote #{OUT_DIR}/stage1.bin, #{OUT_DIR}/stage2.bin, #{OUT_DIR}/break.bin, #{OUT_DIR}/tables.cr"
  end
end

Gen.run
