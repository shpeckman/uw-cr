# spec/wrap_spec.cr

require "./spec_helper"

private def wrapped(s : String, cols : Int32, opts : UW::WrapOpts = UW::WrapOpts.new) : Array(String)
  out = [] of String
  UW.wrap(s, cols, opts: opts).each { |l| out << s.byte_slice(l.offset, l.size) }
  out
end

private def wrapped_widths(s : String, cols : Int32) : Array(Int32)
  out = [] of Int32
  UW.wrap(s, cols).each { |l| out << l.width }
  out
end

describe UW::Utf8Wrap do
  describe "greedy filling" do
    it "packs as many words as fit the budget" do
      wrapped("The quick brown fox jumps over the lazy dog", 12).should eq([
        "The quick", "brown fox", "jumps over", "the lazy dog",
      ])
    end

    it "puts everything on one line when the budget is ample" do
      wrapped("a b c", 80).should eq(["a b c"])
    end

    it "never exceeds the column budget" do
      s = "The quick brown fox jumps over the lazy dog near the river bank"
      (4..30).each do |cols|
        UW.wrap(s, cols).each do |l|
          l.width.should be <= cols
        end
      end
    end

    it "emits one line per word when the budget fits only one" do
      wrapped("aa bb cc", 2).should eq(["aa", "bb", "cc"])
    end

    it "returns nil immediately for empty input" do
      UW.wrap("", 10).next?.should be_nil
    end
  end

  describe "trailing whitespace" do
    it "trims trailing spaces from the emitted line" do
      wrapped("ab   cd", 4).should eq(["ab", "cd"])
    end

    it "excludes trailing spaces from the reported width" do
      wrapped_widths("ab   cd", 4).should eq([2, 2])
    end

    it "keeps interior spaces and counts them" do
      wrapped_widths("a b c", 80).should eq([5])
    end

    it "retains trailing whitespace when trim is disabled" do
      opts = UW::WrapOpts.new.with_trim(false)
      wrapped("ab cd", 2, opts).should eq(["ab ", "cd"])
    end
  end

  describe "mandatory breaks" do
    it "breaks at a line feed regardless of remaining budget" do
      wrapped("ab\ncd", 80).should eq(["ab", "cd"])
    end

    it "flags the line ending at a hard break as mandatory" do
      flags = [] of Bool
      UW.wrap("ab\ncd ef", 80).each { |l| flags << l.mandatory }
      flags.should eq([true, true])
    end

    it "does not flag a soft wrap as mandatory" do
      flags = [] of Bool
      UW.wrap("aaa bbb", 3).each { |l| flags << l.mandatory }
      flags.should eq([false, true])
    end

    it "treats CR LF as a single hard break" do
      wrapped("ab\r\ncd", 80).should eq(["ab", "cd"])
    end

    it "produces an empty line for a blank line" do
      wrapped("a\n\nb", 80).should eq(["a", "", "b"])
    end
  end

  describe "overlong segments" do
    it "hard-breaks a word longer than the budget" do
      wrapped("supercalifragilistic ok", 8).should eq(["supercal", "ifragili", "stic ok"])
    end

    it "leaves an overlong word intact when break_overlong is disabled" do
      opts = UW::WrapOpts.new.with_break_overlong(false)
      wrapped("supercalifragilistic ok", 8).size.should be > wrapped("supercalifragilistic ok", 8, opts).size
    end

    it "still advances when a single cluster exceeds the budget" do
      lines = wrapped("\u65E5\u672C", 1)
      lines.should eq(["\u65E5", "\u672C"])
    end

    it "never splits a wide cluster across the boundary" do
      UW.wrap("\u65E5\u672C\u8A9E", 3).each { |l| l.width.should be <= 3 }
    end
  end

  describe "wide and complex text" do
    it "wraps CJK at ideograph boundaries counting two columns each" do
      wrapped("\u65E5\u672C\u8A9E\u306E\u30C6", 4).should eq([
        "\u65E5\u672C", "\u8A9E\u306E", "\u30C6",
      ])
    end

    it "keeps an emoji ZWJ sequence on one line" do
      wrapped("\u{1F468}\u200D\u{1F469} x", 2).should eq(["\u{1F468}\u200D\u{1F469}", "x"])
    end

    it "keeps a grouped number together" do
      wrapped("cost 1,000 now", 6).should eq(["cost", "1,000", "now"])
    end

    it "counts a combining sequence as one column" do
      wrapped_widths("e\u0301e\u0301 x", 2).should eq([2, 1])
    end
  end

  describe "offsets" do
    it "reports offsets that slice out content free of edge whitespace" do
      s = "alpha beta gamma delta"
      UW.wrap(s, 11).each do |l|
        part = s.byte_slice(l.offset, l.size)
        part.should_not be_empty
        part.starts_with?(' ').should be_false
        part.ends_with?(' ').should be_false
      end
    end

    it "produces strictly increasing offsets" do
      s    = "one two three four five six seven"
      last = -1
      UW.wrap(s, 9).each do |l|
        l.offset.should be > last
        last = l.offset
      end
    end

    it "reconstructs the text when joined with single spaces" do
      s     = "one two three four five"
      parts = wrapped(s, 9)
      parts.join(" ").should eq(s)
    end
  end

  describe "options" do
    it "treats a non-positive budget as no width wrapping" do
      wrapped("a b c d e", 0).should eq(["a b c d e"])
    end

    it "still honours hard breaks with a non-positive budget" do
      wrapped("a b\nc d", 0).should eq(["a b", "c d"])
    end

    it "wraps differently under legacy width mode" do
      s      = "\u2764\uFE0F\u2764\uFE0F"
      uni    = UW.wrap(s, 2, opts: UW::WrapOpts.unicode)
      legacy = UW.wrap(s, 2, opts: UW::WrapOpts.legacy)
      u      = 0
      l      = 0
      uni.each { u += 1 }
      legacy.each { l += 1 }
      u.should be > l
    end

    it "reuses one iterator across buffers via reset" do
      it2   = UW.wrap("aa bb", 2)
      first = [] of Int32
      it2.each { |l| first << l.size }
      it2.reset("cc dd ee".to_slice, 2)
      second = [] of Int32
      it2.each { |l| second << l.size }
      first.should eq([2, 2])
      second.should eq([2, 2, 2])
    end
  end
end

describe UW::Utf32Wrap do
  it "agrees with the utf8 path on line widths" do
    s     = "The quick brown fox jumps over the lazy dog"
    cps   = s.chars.map(&.ord.to_u32)
    slice = Slice(UInt32).new(cps.size) { |i| cps[i] }
    a     = [] of Int32
    b     = [] of Int32
    UW.wrap(slice, 12).each { |l| a << l.width }
    UW.wrap(s, 12).each { |l| b << l.width }
    a.should eq(b)
  end

  it "reports offsets in code points" do
    cps   = "ab cd".chars.map(&.ord.to_u32)
    slice = Slice(UInt32).new(cps.size) { |i| cps[i] }
    offs  = [] of Int32
    UW.wrap(slice, 2).each { |l| offs << l.offset }
    offs.should eq([0, 3])
  end
end
