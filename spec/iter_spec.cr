# spec/iter_spec.cr

require "./spec_helper"

private def ref_utf32(cps : Slice(UInt32)) : Array({Int32, Int32})
  out = [] of {Int32, Int32}
  off = 0
  while off < cps.size
    w, len = UW.width(cps + off)
    out << {w, len}
    off += len
  end
  out
end

private def ref_utf8(bytes : Bytes) : Array({Int32, Int32})
  out = [] of {Int32, Int32}
  off = 0
  while off < bytes.size
    w, len = UW.width(bytes + off)
    out << {w, len}
    off += len
  end
  out
end

private def iter_utf32(cps : Slice(UInt32)) : Array({Int32, Int32})
  out = [] of {Int32, Int32}
  UW.clusters(cps).each { |s| out << {s.width, s.size} }
  out
end

private def iter_utf8(bytes : Bytes) : Array({Int32, Int32})
  out = [] of {Int32, Int32}
  UW.clusters(bytes).each { |s| out << {s.width, s.size} }
  out
end

describe UW::Utf32Clusters do
  it "returns nil immediately for empty input" do
    UW.clusters(Slice(UInt32).empty).next?.should be_nil
  end

  it "yields one span per cluster with correct width and size" do
    spans = iter_utf32(SpecHelper.cps('e'.ord, 0x0301, 'x'.ord, 0x4E00))
    spans.should eq([{1, 2}, {1, 1}, {2, 1}])
  end

  it "carries state across the whole buffer for regional indicators" do
    spans = iter_utf32(SpecHelper.cps(0x1F1E6, 0x1F1E7, 0x1F1E8, 0x1F1E9))
    spans.should eq([{2, 2}, {2, 2}])
  end

  it "matches the reference width loop on every UCD case" do
    SpecHelper.grapheme_cases.each do |c|
      next if c.cps.empty?
      iter_utf32(c.cps).should eq(ref_utf32(c.cps))
    end
  end

  it "tags tab, control and graphemic spans by kind" do
    kinds = [] of UW::SpanKind
    UW.clusters(SpecHelper.cps('a'.ord, 0x09, 0x1B, 'b'.ord)).each { |s| kinds << s.kind }
    kinds.should eq([
      UW::SpanKind::Graphemic,
      UW::SpanKind::Tab,
      UW::SpanKind::Control,
      UW::SpanKind::Graphemic,
    ])
  end

  it "tags a standalone CR and a standalone LF distinctly" do
    cr = [] of UW::SpanKind
    UW.clusters(SpecHelper.cps(0x0D, 'x'.ord)).each { |s| cr << s.kind }
    cr.first.should eq(UW::SpanKind::CR)

    lf = [] of UW::SpanKind
    UW.clusters(SpecHelper.cps(0x0A, 'x'.ord)).each { |s| lf << s.kind }
    lf.first.should eq(UW::SpanKind::LF)
  end

  it "tags a CR LF pair as a single CRLF span" do
    spans = [] of {Int32, UW::SpanKind}
    UW.clusters(SpecHelper.cps(0x0D, 0x0A, 'x'.ord)).each { |s| spans << {s.size, s.kind} }
    spans.first.should eq({2, UW::SpanKind::CRLF})
    spans.size.should eq(2)
  end

  it "reuses one iterator across buffers via reset" do
    it0   = UW.clusters(SpecHelper.cps('a'.ord, 'b'.ord))
    first = [] of Int32
    it0.each { |s| first << s.size }
    it0.reset(SpecHelper.cps(0x4E00, 0x4E01, 0x4E02))
    second = [] of Int32
    it0.each { |s| second << s.width }
    first.should eq([1, 1])
    second.should eq([2, 2, 2])
  end
end

describe UW::Utf8Clusters do
  it "returns nil immediately for empty input" do
    UW.clusters(Bytes.empty).next?.should be_nil
  end

  it "yields spans measured in bytes" do
    spans = iter_utf8("e\u0301x\u4E00".to_slice)
    spans.should eq([{1, 3}, {1, 1}, {2, 3}])
  end

  it "advances one byte on malformed input under Replace" do
    spans = iter_utf8(Bytes[0xFF_u8, 'a'.ord.to_u8])
    spans.should eq([{1, 1}, {1, 1}])
  end

  it "stops at malformed input under Strict" do
    out = [] of {Int32, Int32}
    UW.clusters(Bytes[0xFF_u8, 'a'.ord.to_u8], UW::Utf8Policy::Strict).each { |s| out << {s.width, s.size} }
    out.should be_empty
  end

  it "matches the reference width loop on every UCD case (utf8)" do
    SpecHelper.grapheme_cases.each do |c|
      next if c.cps.empty?
      s = String.build do |io|
        c.cps.each { |cp| io << cp.unsafe_chr }
      end
      bytes = s.to_slice
      iter_utf8(bytes).should eq(ref_utf8(bytes))
    end
  end

  it "tags an ASCII tab span as Tab" do
    kinds = [] of UW::SpanKind
    UW.clusters("a\tb".to_slice).each { |s| kinds << s.kind }
    kinds.should eq([UW::SpanKind::Graphemic, UW::SpanKind::Tab, UW::SpanKind::Graphemic])
  end

  it "tags a CR LF pair as a single CRLF span on the utf8 path" do
    spans = [] of {Int32, UW::SpanKind}
    UW.clusters("\r\nx".to_slice).each { |s| spans << {s.size, s.kind} }
    spans.first.should eq({2, UW::SpanKind::CRLF})
    spans.size.should eq(2)
  end

  it "reuses one iterator across buffers via reset" do
    it0 = UW.clusters("ab".to_slice)
    it0.each { |_| }
    it0.reset("\u4E00\u4E01".to_slice)
    widths = [] of Int32
    it0.each { |s| widths << s.width }
    widths.should eq([2, 2])
  end

  it "sums iterator widths to match swidth over corpora" do
    seeds = [
      "the quick brown fox 0123456789 ",
      "el veloz murciélago hindú ñ ",
      "日本語のテキスト漢字 ",
      "👨‍👩‍👧‍👦 🇯🇵 ❤️ 👍🏽 😀 ",
      "क्षत्रिय हिन्दी संयुक्त ",
    ]
    seeds.each do |seed|
      bytes = seed.to_slice
      total = 0
      UW.clusters(bytes).each { |s| total += s.width if s.width > 0 }
      total.should eq(UW.swidth(bytes))
    end
  end
end
