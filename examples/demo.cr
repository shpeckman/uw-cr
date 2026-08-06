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
    truncate_fit_section
    pad_section
    tabs_section
    line_break_section
    wrap_section
    ansi_section
    mode2027_section
  end

  def self.banner(title : String) : Nil
    puts
    puts UW.center(" #{title} ", 64, RULE[0])
  end

  def self.show(label : String, value : String) : Nil
    printf("  %-22s %s\n", label, value)
  end

  def self.gauge(s : String, opts : UW::WidthOpts = UW::WidthOpts.unicode) : String
    w = UW.swidth(s, opts: opts)
    "#{s}  (#{w} #{w == 1 ? "col" : "cols"})"
  end

  def self.header : Nil
    puts UW.center(" uw-cr demo ", 64, RULE[0])
    show("version", UW::VERSION)
    show("unicode", UW.unicode_version)
    show("crystal", Crystal::VERSION)
  end

  def self.width_basics : Nil
    banner("display width")
    samples = {
      "ascii"          => "hello",
      "cjk"            => "\u65E5\u672C\u8A9E",
      "flag"           => "\u{1F1EF}\u{1F1F5}",
      "family zwj"     => "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}",
      "combining"      => "e\u0301\u0300",
      "vs16 heart"     => "\u2764\uFE0F",
      "wide + narrow"  => "a\u4E00b",
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
        idx, UW.ljust(part, 6), sp.width, sp.size, sp.kind)
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
      printf("  %s at col %-2d (width %d)\n", UW.ljust(part, 3), cell.col, cell.width)
    end
    show("col of byte 4", UW.offset_to_col(s, 4).to_s)
    show("offset at col 3", UW.col_to_offset(s, 3).to_s)

    sl = UW.slice_cols(s, 1, 4)
    show("slice cols 1..4", "#{s.byte_slice(sl.offset, sl.size)}  padL=#{sl.pad_left} padR=#{sl.pad_right}")
  end

  def self.truncate_fit_section : Nil
    banner("truncate & fit")
    s = "\u65E5\u672C\u8A9E is fun"
    show("input", gauge(s))
    [4, 6, 9].each do |cols|
      w, off = UW.truncate(s, cols)
      show("truncate #{cols}", "#{s.byte_slice(0, off)}  #{ARROW} #{w} cols")
    end
    [4, 6, 9].each do |cols|
      show("fit #{cols}", UW.fit(s, cols))
    end
    show("fit_pad 12 center", "[#{UW.fit_pad(s, 12, UW::Align::Center)}]")
  end

  def self.pad_section : Nil
    banner("padding & alignment")
    s = "\u65E5x"
    show("ljust 8", "[#{UW.ljust(s, 8)}]")
    show("rjust 8", "[#{UW.rjust(s, 8)}]")
    show("center 8", "[#{UW.center(s, 8)}]")
    show("center dots", "[#{UW.center("menu", 12, '.')}]")
  end

  def self.tabs_section : Nil
    banner("tab expansion")
    s = "a\tbb\tccc\tend"
    show("raw width", UW.swidth_tabs(s, 4).to_s)
    show("expanded (4)", "[#{UW.expand_tabs(s, 4)}]")
    show("expanded (8)", "[#{UW.expand_tabs(s, 8)}]")
  end

  def self.line_break_section : Nil
    banner("line break opportunities")
    s = "The quick-brown fox, 3.14 \u65E5\u672C!"
    show("input", s)
    off = 0
    UW.line_breaks(s).each do |b|
      part = s.byte_slice(off, b.size)
      mark = b.mandatory ? "\u00B6" : ARROW
      printf("  %s %s (w=%d)\n", UW.ljust("[#{part}]", 16), mark, b.width)
      off += b.size
    end
  end

  def self.wrap_section : Nil
    banner("wrapping")
    s = "The quick brown fox jumps over the lazy dog near the river bank"
    show("input", "#{s.size} chars")
    [12, 20, 30].each do |cols|
      puts "  #{RULE * 2} #{cols} cols #{RULE * 2}"
      UW.wrap(s, cols).each do |line|
        part = s.byte_slice(line.offset, line.size)
        printf("  |%-#{cols}s| w=%d\n", part, line.width)
      end
    end

    banner("wrapping with hard breaks & CJK")
    s2 = "short\n\n\u65E5\u672C\u8A9E\u306E\u30C6\u30AD\u30B9\u30C8 end"
    UW.wrap(s2, 8).each do |line|
      part = s2.byte_slice(line.offset, line.size)
      mark = line.mandatory ? "\u00B6" : " "
      printf("  |%s|%s w=%d\n", part, mark, line.width)
    end
  end

  def self.ansi_section : Nil
    banner("ansi-aware")
    colored = "\e[31mred\e[0m and \e[1;32mbold green\e[0m text here"
    show("raw bytes", colored.bytesize.to_s)
    show("stripped", UW::Ansi.strip(colored))
    show("visible width", UW::Ansi.swidth(colored).to_s)

    puts "  #{RULE * 2} truncate keeping color #{RULE * 2}"
    t = UW::Ansi.truncate(colored, 10, "\u2026")
    show("truncated", t)
    show("truncated stripped", UW::Ansi.strip(t))

    puts "  #{RULE * 2} wrap keeping color #{RULE * 2}"
    UW::Ansi.wrap(colored, 12).each do |wl|
      show("line", "#{wl.text}  (w=#{wl.width})")
    end
  end

  def self.mode2027_section : Nil
    banner("legacy vs unicode width")
    samples = {
      "vs16 heart"  => "\u2764\uFE0F",
      "family zwj"  => "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}",
      "flag"        => "\u{1F1EF}\u{1F1F5}",
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