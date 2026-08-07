# examples/demo.cr

require "../src/uw-cr"

module Demo
  RULE  = "─"
  ARROW = "→"

  def self.run : Nil
    header
    width_basics
    clusters_section
    cells_section
    truncate_section
    line_break_section
    mode2027_section
  end

  def self.banner(title : String) : Nil
    puts
    puts center_rule(" #{title} ", 64)
  end

  def self.center_rule(s : String, cols : Int32) : String
    w = UW.swidth(s)
    return s if w >= cols
    deficit = cols - w
    left    = deficit // 2
    right   = deficit - left
    String.build do |io|
      left.times { io << RULE }
      io << s
      right.times { io << RULE }
    end
  end

  def self.pad_right(s : String, cols : Int32) : String
    w = UW.swidth(s)
    return s if w >= cols
    String.build do |io|
      io << s
      (cols - w).times { io << ' ' }
    end
  end

  def self.show(label : String, value : String) : Nil
    printf("  %-22s %s\n", label, value)
  end

  def self.gauge(s : String, opts : UW::WidthOpts = UW::WidthOpts.unicode) : String
    w = UW.swidth(s, opts: opts)
    "#{s}  (#{w} #{w == 1 ? "col" : "cols"})"
  end

  def self.header : Nil
    puts center_rule(" uw-cr demo ", 64)
    show("version", UW::VERSION)
    show("unicode", UW.unicode_version)
    show("crystal", Crystal::VERSION)
  end

  def self.width_basics : Nil
    banner("display width")
    samples = {
      "ascii"         => "hello",
      "cjk"           => "\u65E5\u672C\u8A9E",
      "flag"          => "\u{1F1EF}\u{1F1F5}",
      "family zwj"    => "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}",
      "combining"     => "e\u0301\u0300",
      "vs16 heart"    => "\u2764\uFE0F",
      "wide + narrow" => "a\u4E00b",
    }
    samples.each { |name, s| show(name, gauge(s)) }
  end

  def self.clusters_section : Nil
    banner("grapheme clusters")
    s = "a\u0301\u65E5\u{1F1EF}\u{1F1F5}\u{1F468}\u200D\u{1F469}"
    show("input", s)
    idx = 0
    off = 0
    UW.clusters(s).each do |sp|
      part = s.byte_slice(off, sp.size)
      printf("  [%d] %s width=%d bytes=%-2d kind=%s\n",
        idx, pad_right(part, 6), sp.width, sp.size, sp.kind)
      off += sp.size
      idx += 1
    end
    show("cluster count", idx.to_s)
  end

  def self.cells_section : Nil
    banner("column mapping")
    s = "a\u4E00b\u4E01c"
    show("input", gauge(s))
    UW.cells(s).each do |cell|
      part = s.byte_slice(cell.offset, cell.size)
      printf("  %s at col %-2d (width %d)\n", pad_right(part, 3), cell.col, cell.width)
    end
    show("col of byte 4", UW.offset_to_col(s, 4).to_s)
    show("offset at col 3", UW.col_to_offset(s, 3).to_s)

    sl = UW.slice_cols(s, 1, 4)
    show("slice cols 1..4", "#{s.byte_slice(sl.offset, sl.size)}  padL=#{sl.pad_left} padR=#{sl.pad_right}")
  end

  def self.truncate_section : Nil
    banner("truncate")
    s = "\u65E5\u672C\u8A9E is fun"
    show("input", gauge(s))
    [4, 6, 9].each do |cols|
      w, off = UW.truncate(s, cols)
      show("truncate #{cols}", "#{s.byte_slice(0, off)}  #{ARROW} #{w} cols")
    end
  end

  def self.line_break_section : Nil
    banner("line break opportunities")
    s = "The quick-brown fox, 3.14 \u65E5\u672C!"
    show("input", s)
    off = 0
    UW.line_breaks(s).each do |b|
      part = s.byte_slice(off, b.size)
      mark = b.mandatory ? "\u00B6" : ARROW
      printf("  %s %s (w=%d)\n", pad_right("[#{part}]", 16), mark, b.width)
      off += b.size
    end
  end

  def self.mode2027_section : Nil
    banner("legacy vs unicode width")
    samples = {
      "vs16 heart" => "\u2764\uFE0F",
      "family zwj" => "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}",
      "flag"       => "\u{1F1EF}\u{1F1F5}",
    }
    printf("  %-14s %8s %8s\n", "sample", "unicode", "legacy")
    samples.each do |name, s|
      u = UW.swidth(s, opts: UW::WidthOpts.unicode)
      l = UW.swidth(s, opts: UW::WidthOpts.legacy)
      printf("  %-14s %8d %8d\n", name, u, l)
    end

    banner("ambiguous width")
    amb = "\u00A7\u00B1\u2103"
    show("default (narrow)", gauge(amb))
    show("ambiguous_wide", gauge(amb, UW::WidthOpts.unicode.with_ambiguous_wide(true)))

    banner("config resolution (mode:2027)")
    on  = UW::Config.new(supported: true, state: UW::Mode2027State::Set)
    off = UW::Config.new(supported: true, state: UW::Mode2027State::Reset)
    no  = UW::Config.new(supported: false, state: UW::Mode2027State::Set)
    show("set + supported", "#{on.width_mode} (grapheme=#{on.grapheme_processing?})")
    show("reset + supported", "#{off.width_mode} (grapheme=#{off.grapheme_processing?})")
    show("set + unsupported", "#{no.width_mode} (grapheme=#{no.grapheme_processing?})")
  end
end

Demo.run