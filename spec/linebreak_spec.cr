# spec/linebreak_spec.cr

require "./spec_helper"

private def lb_positions(cps : Slice(UInt32)) : Array(Bool)
  out = Array(Bool).new(cps.size, false)
  off = 0
  UW.line_breaks(cps).each do |b|
    out[off] = true if off < cps.size && off > 0
    off += b.size
  end
  out
end

private def segments(s : String) : Array(String)
  out = [] of String
  off = 0
  UW.line_breaks(s).each do |b|
    out << s.byte_slice(off, b.size)
    off += b.size
  end
  out
end

describe UW::LineState do
  describe "Unicode LineBreakTest.txt (17.0.0)" do
    cases = SpecHelper.line_cases

    it "loads the official test cases" do
      cases.size.should be > 10_000
    end

    it "produces the exact break opportunity at every position for all cases" do
      failures = [] of String
      cases.each do |c|
        got  = lb_positions(c.cps)
        want = c.breaks[0, c.cps.size]
        want[0] = false if c.cps.size > 0
        failures << "line #{c.line}: #{c.comment}" if got != want
      end
      failures.first(10).should eq([] of String)
    end

    it "never reports a break at the start of text (LB2)" do
      cases.each do |c|
        next if c.cps.size == 0
        c.breaks[0].should be_false
      end
    end
  end

  describe "targeted rule cases" do
    it "breaks after a space and keeps the space with the preceding word (LB18)" do
      segments("ab cd").should eq(["ab ", "cd"])
    end

    it "collapses a run of spaces into the preceding segment" do
      segments("ab   cd").should eq(["ab   ", "cd"])
    end

    it "does not break before closing punctuation (LB13)" do
      segments("ab \u007Dcd").should eq(["ab \u007D", "cd"])
      segments("ab !cd").should eq(["ab !", "cd"])
    end

    it "binds a closing parenthesis to a following letter (LB30)" do
      segments("a )b").should eq(["a )b"])
    end

    it "does not break after opening punctuation (LB14)" do
      segments("( ab").should eq(["( ab"])
    end

    it "does not break inside a grouped number (LB25)" do
      segments("1,000 x").should eq(["1,000 ", "x"])
    end

    it "does not break between a currency prefix and a number (LB25)" do
      segments("$5 x").should eq(["$5 ", "x"])
    end

    it "does not break between digits and letters (LB23)" do
      segments("12ab x").should eq(["12ab ", "x"])
    end

    it "allows a break after a hyphen (LB21)" do
      segments("well-known").should eq(["well-", "known"])
    end

    it "does not break after a word-initial hyphen (LB20a)" do
      segments("-abc").should eq(["-abc"])
    end

    it "does not break before an ellipsis (LB22)" do
      segments("ab\u2026").should eq(["ab\u2026"])
    end

    it "does not break around a word joiner (LB11)" do
      segments("a\u2060b").should eq(["a\u2060b"])
    end

    it "does not break after a no-break space (LB12)" do
      segments("a\u00A0b").should eq(["a\u00A0b"])
    end

    it "breaks between ideographs (LB31)" do
      segments("\u65E5\u672C").should eq(["\u65E5", "\u672C"])
    end

    it "keeps an emoji ZWJ sequence together (LB8a)" do
      segments("\u{1F468}\u200D\u{1F469}").should eq(["\u{1F468}\u200D\u{1F469}"])
    end

    it "keeps a regional indicator pair together (LB30a)" do
      segments("\u{1F1EB}\u{1F1F7}\u{1F1EB}\u{1F1F7}").should eq(["\u{1F1EB}\u{1F1F7}", "\u{1F1EB}\u{1F1F7}"])
    end

    it "attaches a combining mark to its base (LB9)" do
      segments("e\u0301 x").should eq(["e\u0301 ", "x"])
    end
  end

  describe "mandatory breaks" do
    it "marks a line feed as mandatory (LB4/LB5)" do
      spans = [] of Bool
      UW.line_breaks("a\nb").each { |b| spans << b.mandatory }
      spans.should eq([true, true])
    end

    it "keeps CR LF as a single mandatory break (LB5)" do
      sizes = [] of Int32
      UW.line_breaks("a\r\nb").each { |b| sizes << b.size }
      sizes.should eq([3, 1])
    end

    it "marks the final segment as mandatory at end of text (LB3)" do
      last = nil.as(UW::BreakSpan?)
      UW.line_breaks("ab cd").each { |b| last = b }
      last.not_nil!.mandatory.should be_true
    end

    it "does not mark an interior opportunity as mandatory" do
      first = UW.line_breaks("ab cd").next?
      first.not_nil!.mandatory.should be_false
    end
  end

  describe "spans" do
    it "reports the display width of each segment" do
      widths = [] of Int32
      UW.line_breaks("\u65E5\u672C ab").each { |b| widths << b.width }
      widths.should eq([2, 3, 2])
    end

    it "sums segment sizes to the full byte length" do
      s     = "Hello, world! \u65E5\u672C\u8A9E 1,234.5"
      total = 0
      UW.line_breaks(s).each { |b| total += b.size }
      total.should eq(s.bytesize)
    end

    it "returns nil immediately for empty input" do
      UW.line_breaks("").next?.should be_nil
    end

    it "reports the first opportunity via line_break_next" do
      UW.line_break_next("ab cd").should eq(3)
    end

    it "reuses one iterator across buffers via reset" do
      it2 = UW.line_breaks("ab cd")
      it2.next?.not_nil!.size.should eq(3)
      it2.reset("xy z".to_slice)
      it2.next?.not_nil!.size.should eq(3)
    end
  end
end

describe UW::Utf32LineBreaks do
  it "agrees with the utf8 path on segment counts" do
    s     = "The quick brown fox, 3.14 times!"
    cps   = s.chars.map(&.ord.to_u32)
    slice = Slice(UInt32).new(cps.size) { |i| cps[i] }
    a     = 0
    b     = 0
    UW.line_breaks(slice).each { a += 1 }
    UW.line_breaks(s).each { b += 1 }
    a.should eq(b)
  end
end
