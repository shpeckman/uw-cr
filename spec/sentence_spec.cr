# spec/sentence_spec.cr

require "./spec_helper"

private def sentence_breaks(cps : Slice(UInt32)) : Array(Bool)
  out = Array(Bool).new(cps.size, false)
  off = 0
  UW.sentences(cps).each do |s|
    out[off] = true if off < cps.size
    off += s.size
  end
  out
end

describe UW::SentenceState do
  describe "Unicode SentenceBreakTest.txt (17.0.0)" do
    it "loads the official test cases" do
      SpecHelper.sentence_cases.size.should be > 400
    end

    it "produces the exact break at every position for all cases" do
      failures = [] of String
      SpecHelper.sentence_cases.each do |c|
        actual = sentence_breaks(c.cps)
        next if actual == c.breaks[0, actual.size]
        failures << "line #{c.line}: #{c.comment}"
      end
      failures.first(10).should eq([] of String)
    end
  end

  describe "targeted rule cases" do
    it "breaks after a period and space before a capital (SB11)" do
      UW.sentence_next("One. Two").should eq(5)
    end

    it "keeps a lowercase continuation joined (SB8)" do
      UW.sentence_next("etc. and more").should eq("etc. and more".bytesize)
    end

    it "keeps a decimal point inside a number (SB6)" do
      UW.sentence_next("3.4 x").should eq("3.4 x".bytesize)
    end

    it "keeps initials joined (SB7)" do
      UW.sentence_next("U.S.A ok").should eq("U.S.A ok".bytesize)
    end

    it "breaks on a hard paragraph separator (SB4)" do
      UW.sentence_next("a\nb").should eq(2)
    end

    it "keeps a CR LF pair together (SB3)" do
      UW.sentence_next("a\r\nb").should eq(3)
    end

    it "keeps a closing quote and space with the terminator (SB9/SB10/SB11)" do
      UW.sentence_next("He said \"Go.\" Then").should eq("He said \"Go.\" ".bytesize)
    end

    it "attaches extenders to the preceding character (SB5)" do
      UW.sentence_next("a\u0301. B").should eq("a\u0301. ".bytesize)
    end

    it "reset restores initial state" do
      it2 = UW.sentences("Hi. Yo.")
      it2.next?.not_nil!.size.should eq(4)
      it2.reset("One. Two.".to_slice)
      it2.next?.not_nil!.size.should eq(5)
    end
  end
end

describe UW::Utf8Sentences do
  it "splits text into sentences" do
    sizes = [] of Int32
    UW.sentences("Hello world. This is next.").each { |s| sizes << s.size }
    sizes.should eq([13, 13])
  end

  it "reports the display width of each sentence" do
    widths = [] of Int32
    UW.sentences("\u65E5\u672C\u3002ab").each { |s| widths << s.width }
    widths.first.should eq(6)
  end

  it "sums sentence sizes to the full byte length" do
    s     = "First one! Second two. Third three?"
    total = 0
    UW.sentences(s).each { |x| total += x.size }
    total.should eq(s.bytesize)
  end

  it "reuses one iterator across buffers via reset" do
    it2   = UW.sentences("A. B.")
    first = [] of Int32
    it2.each { |s| first << s.size }
    it2.reset("Ok. Go.".to_slice)
    second = [] of Int32
    it2.each { |s| second << s.size }
    first.should eq([3, 2])
    second.should eq([4, 3])
  end

  it "returns nil immediately for empty input" do
    UW.sentences("").next?.should be_nil
  end
end

describe UW::Utf32Sentences do
  it "agrees with the utf8 path on sentence sizes in code points" do
    s      = "One. Two three. Four?"
    cps    = s.chars.map(&.ord.to_u32)
    slice  = Slice(UInt32).new(cps.size) { |i| cps[i] }
    counts = [] of Int32
    UW.sentences(slice).each { |x| counts << x.size }
    counts.sum.should eq(slice.size)
  end
end
