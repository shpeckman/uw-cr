# spec/word_spec.cr

require "./spec_helper"

private def word_breaks(cps : Slice(UInt32)) : Array(Bool)
  out = Array(Bool).new(cps.size, false)
  off = 0
  UW.words(cps).each do |w|
    out[off] = true if off < cps.size
    off += w.size
  end
  out
end

describe UW::WordState do
  describe "Unicode WordBreakTest.txt (17.0.0)" do
    it "loads the official test cases" do
      SpecHelper.word_cases.size.should be > 1000
    end

    it "produces the exact break at every position for all cases" do
      failures = [] of String
      SpecHelper.word_cases.each do |c|
        actual = word_breaks(c.cps)
        next if actual == c.breaks[0, actual.size]
        failures << "line #{c.line}: #{c.comment}"
      end
      failures.first(10).should eq([] of String)
    end
  end

  describe "targeted rule cases" do
    it "breaks between a letter and a space (WB999)" do
      UW.word_next("hi there").should eq(2)
    end

    it "keeps a letter run together (WB5)" do
      UW.word_next("hello, world").should eq(5)
    end

    it "keeps an apostrophe inside a word (WB6/WB7)" do
      UW.word_next("can't stop").should eq(5)
    end

    it "keeps a decimal number together (WB11/WB12)" do
      UW.word_next("3.14 pie").should eq(4)
    end

    it "keeps a letter-number run together (WB9/WB10)" do
      UW.word_next("a1b2 x").should eq(4)
    end

    it "attaches combining marks to the base word (WB4)" do
      UW.word_next("e\u0301t\u0301 x").should eq(6)
    end

    it "keeps an emoji ZWJ sequence as one word (WB3c)" do
      UW.word_next("\u{1F468}\u200D\u{1F469}").should eq(11)
    end

    it "pairs regional indicators (WB15/WB16)" do
      UW.word_next("\u{1F1EB}\u{1F1F7}\u{1F1EB}\u{1F1F7}").should eq(8)
    end

    it "keeps a CR LF pair together (WB3)" do
      UW.word_next("\r\na").should eq(2)
    end

    it "keeps extend-num-let joined runs together (WB13a/WB13b)" do
      UW.word_next("a_b c").should eq(3)
    end

    it "reset restores initial state" do
      it2 = UW.words("ab")
      it2.next?.not_nil!.size.should eq(2)
      it2.next?.should be_nil
      it2.reset("cd".to_slice)
      it2.next?.not_nil!.size.should eq(2)
    end
  end
end

describe UW::Utf8Words do
  it "splits a sentence into words and separators" do
    sizes = [] of Int32
    UW.words("Hi there!").each { |w| sizes << w.size }
    sizes.should eq([2, 1, 5, 1])
  end

  it "reports the display width of each word" do
    widths = [] of Int32
    UW.words("\u65E5\u672C ab").each { |w| widths << w.width }
    widths.should eq([2, 2, 1, 2])
  end

  it "sums word sizes to the full byte length" do
    s     = "The quick brown fox, 3.14 times! \u{1F468}\u200D\u{1F469}"
    total = 0
    UW.words(s).each { |w| total += w.size }
    total.should eq(s.bytesize)
  end

  it "reuses one iterator across buffers via reset" do
    it2   = UW.words("ab cd")
    first = [] of Int32
    it2.each { |w| first << w.size }
    it2.reset("xy".to_slice)
    second = [] of Int32
    it2.each { |w| second << w.size }
    first.should eq([2, 1, 2])
    second.should eq([2])
  end

  it "returns nil immediately for empty input" do
    UW.words("").next?.should be_nil
  end
end

describe UW::Utf32Words do
  it "agrees with the utf8 path on word sizes in code points" do
    s      = "Hello, world 42.5 times"
    cps    = s.chars.map(&.ord.to_u32)
    slice  = Slice(UInt32).new(cps.size) { |i| cps[i] }
    counts = [] of Int32
    UW.words(slice).each { |w| counts << w.size }
    counts.sum.should eq(slice.size)
  end
end
