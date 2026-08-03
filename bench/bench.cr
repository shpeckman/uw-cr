# bench/bench.cr

require "benchmark"
require "../src/uw-cr"

module Bench
  TARGET_BYTES = 256 * 1024
  WARMUP       = 500.milliseconds
  CALCULATION  = 1500.milliseconds

  SEEDS = {
    "ascii"     => "the quick brown fox jumps over the lazy dog 0123456789 ",
    "latin"     => "el veloz murciélago hindú comía feliz cardillo y kiwi ñ ",
    "combining" => "e\u0301a\u0300o\u0308u\u0304i\u0303n\u0303c\u0327s\u030Cz\u0307 ",
    "cjk"       => "日本語のテキストと漢字が混ざった文字列です。",
    "hangul"    => "한국어 텍스트와 자모 조합 \u1100\u1161\u11A8 입니다 ",
    "indic"     => "क्षत्रिय हिन्दी का संयुक्त अक्षर परीक्षण ",
    "emoji"     => "👨‍👩‍👧‍👦 🇯🇵 ❤️ 👍🏽 🧑‍💻 😀 ",
    "mixed"     => "a日本👨‍👩‍👧b🇯🇵c e\u0301 क्ष d ",
  }

  UTF8_UNI    = "swidth utf8 uni"
  UTF8_LEG    = "swidth utf8 legacy"
  UTF32_UNI   = "swidth utf32 uni"
  UTF32_LEG   = "swidth utf32 legacy"
  UTF8_ITER   = "cluster iter utf8"
  UTF8_STREAM = "cluster stream utf8"
  STDLIB_SEG  = "stdlib grapheme_size"
  SCALAR_CP   = "width_cp scalar"

  UNI_OPTS = UW::WidthOpts.unicode
  LEG_OPTS = UW::WidthOpts.legacy

  @@sink = 0_i64

  def self.consume(value : Int32) : Nil
    @@sink &+= value
  end

  def self.sink : Int64
    @@sink
  end

  struct Corpus
    getter name      : String
    getter text      : String
    getter bytes     : Bytes
    getter cps       : Slice(UInt32)
    getter clusters  : Int32
    getter width_uni : Int32
    getter width_leg : Int32

    def initialize(@name : String, seed : String)
      @text  = seed * ((TARGET_BYTES // seed.bytesize) + 1)
      @bytes = @text.to_slice
      cps    = Slice(UInt32).new(@text.size, 0_u32)
      i      = 0
      @text.each_char do |ch|
        cps[i] = ch.ord.to_u32
        i += 1
      end
      @cps       = cps
      @clusters  = Bench.count_clusters(@bytes)
      @width_uni = UW.swidth(@text, opts: UNI_OPTS)
      @width_leg = UW.swidth(@text, opts: LEG_OPTS)
    end
  end

  record Result,
    group  : String,
    mode   : String,
    corpus : String,
    bytes  : Int32,
    items  : Int32,
    entry  : Benchmark::IPS::Entry

  def self.count_clusters(bytes : Bytes) : Int32
    off = 0
    n   = 0
    while off < bytes.size
      _, len = UW.width(bytes + off)
      off += len
      n += 1
    end
    n
  end

  def self.iter_width(bytes : Bytes) : Int32
    off   = 0
    total = 0
    while off < bytes.size
      w, len = UW.width(bytes + off)
      total += w
      off += len
    end
    total
  end

  def self.stream_width(bytes : Bytes) : Int32
    total = 0
    UW.clusters(bytes).each { |s| total += s.width }
    total
  end

  def self.scalar_width(cps : Slice(UInt32)) : Int32
    total = 0
    cps.each { |cp| total += UW.width_cp(cp) }
    total
  end

  def self.corpora : Array(Corpus)
    SEEDS.to_a.map { |(name, seed)| Corpus.new(name, seed) }
  end

  def self.print_inputs(list : Array(Corpus)) : Nil
    puts "uw-cr #{UW::VERSION} | UCD #{UW.unicode_version} | crystal #{Crystal::VERSION} | #{Crystal::DESCRIPTION.lines.first?}"
    puts
    printf("%-10s %10s %10s %10s %10s %10s %8s\n",
      "corpus", "bytes", "cps", "clusters", "w:uni", "w:legacy", "b/cl")
    list.each do |c|
      printf("%-10s %10d %10d %10d %10d %10d %8.2f\n",
        c.name, c.bytes.size, c.cps.size, c.clusters, c.width_uni, c.width_leg,
        c.bytes.size / c.clusters.to_f)
    end
    puts
  end

  def self.print_summary(results : Array(Result)) : Nil
    puts
    printf("%-22s %-8s %-10s %12s %12s %12s\n",
      "group", "mode", "corpus", "ns/op", "MiB/s", "Mitem/s")
    results.group_by(&.group).each do |group, rows|
      rows.each do |r|
        mean = r.entry.mean
        printf("%-22s %-8s %-10s %12.0f %12.1f %12.2f\n",
          group,
          r.mode,
          r.corpus,
          1.0e9 / mean,
          r.bytes * mean / (1024.0 * 1024.0),
          r.items * mean / 1.0e6)
      end
    end
    puts
    puts "sink #{sink}"
  end

  def self.run : Nil
    list = corpora
    print_inputs(list)

    results = [] of Result
    Benchmark.ips(calculation: CALCULATION, warmup: WARMUP) do |x|
      list.each do |c|
        results << Result.new(UTF8_UNI, "uni", c.name, c.bytes.size, c.clusters,
          x.report("#{UTF8_UNI} #{c.name}") { consume(UW.swidth(c.bytes, opts: UNI_OPTS)) })
      end
      list.each do |c|
        results << Result.new(UTF8_LEG, "legacy", c.name, c.bytes.size, c.clusters,
          x.report("#{UTF8_LEG} #{c.name}") { consume(UW.swidth(c.bytes, opts: LEG_OPTS)) })
      end
      list.each do |c|
        results << Result.new(UTF32_UNI, "uni", c.name, c.cps.size * 4, c.clusters,
          x.report("#{UTF32_UNI} #{c.name}") { consume(UW.swidth(c.cps, opts: UNI_OPTS)) })
      end
      list.each do |c|
        results << Result.new(UTF32_LEG, "legacy", c.name, c.cps.size * 4, c.clusters,
          x.report("#{UTF32_LEG} #{c.name}") { consume(UW.swidth(c.cps, opts: LEG_OPTS)) })
      end
      list.each do |c|
        results << Result.new(UTF8_ITER, "uni", c.name, c.bytes.size, c.clusters,
          x.report("#{UTF8_ITER} #{c.name}") { consume(iter_width(c.bytes)) })
      end
      list.each do |c|
        results << Result.new(UTF8_STREAM, "uni", c.name, c.bytes.size, c.clusters,
          x.report("#{UTF8_STREAM} #{c.name}") { consume(stream_width(c.bytes)) })
      end
      list.each do |c|
        results << Result.new(STDLIB_SEG, "-", c.name, c.bytes.size, c.clusters,
          x.report("#{STDLIB_SEG} #{c.name}") { consume(c.text.grapheme_size) })
      end
      list.each do |c|
        results << Result.new(SCALAR_CP, "uni", c.name, c.cps.size * 4, c.cps.size,
          x.report("#{SCALAR_CP} #{c.name}") { consume(scalar_width(c.cps)) })
      end
    end

    print_summary(results)
  end
end

Bench.run
