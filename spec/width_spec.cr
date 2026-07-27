# spec/width_spec.cr

require "./spec_helper"

describe UW do
  describe ".width (cluster, UTF-32)" do
    it "measures a bare wide char as 2" do
      UW.width(SpecHelper.cps(0x4E00)).should eq({2, 1})
    end

    it "measures a control cluster as -1" do
      w, _ = UW.width(SpecHelper.cps(0x1B))
      w.should eq(-1)
    end

    it "counts a base plus combining mark as one narrow cluster" do
      UW.width(SpecHelper.cps('e'.ord, 0x0301)).should eq({1, 2})
    end

    it "widens a narrow emoji base under VS16" do
      UW.width(SpecHelper.cps(0x2764, 0xFE0F)).should eq({2, 2})
    end

    it "narrows an emoji base under VS15" do
      w, _ = UW.width(SpecHelper.cps(0x2764, 0xFE0E))
      w.should eq(1)
    end

    it "measures a regional-indicator flag as 2" do
      UW.width(SpecHelper.cps(0x1F1E6, 0x1F1E7)).should eq({2, 2})
    end

    it "returns zero width and zero consumed for empty input" do
      UW.width(Slice(UInt32).empty).should eq({0, 0})
    end

    it "caps a wide ZWJ sequence at the configured cap" do
      w, _ = UW.width(SpecHelper.cps(0x1F468, 0x200D, 0x1F469))
      w.should eq(UW::CLUSTER_WIDTH_CAP)
    end
  end

  describe ".width (cluster, UTF-8)" do
    it "measures the first grapheme of a string" do
      UW.width("\u00E9x").should eq({1, 2})
    end

    it "advances one byte on malformed input under Replace" do
      _, c = UW.width(Bytes[0xFF_u8, 'a'.ord.to_u8], UW::Utf8Policy::Replace)
      c.should eq(1)
    end

    it "stops at malformed input under Strict" do
      _, c = UW.width(Bytes[0xFF_u8, 'a'.ord.to_u8], UW::Utf8Policy::Strict)
      c.should eq(0)
    end
  end

  describe ".grapheme_next" do
    it "returns the code-unit span of the next cluster" do
      UW.grapheme_next(SpecHelper.cps('e'.ord, 0x0301, 'x'.ord)).should eq(2)
    end

    it "returns 0 for empty input" do
      UW.grapheme_next(Slice(UInt32).empty).should eq(0)
    end

    it "consumes exactly the first cluster of every UCD test case" do
      SpecHelper.grapheme_cases.each do |c|
        next if c.cps.empty?
        # first cluster length = index of the second boundary
        expected = c.breaks.size
        i = 1
        while i < c.breaks.size
          break if c.breaks[i]
          i += 1
        end
        expected = i
        UW.grapheme_next(c.cps).should eq(expected)
      end
    end
  end

  describe ".swidth" do
    it "sums printable cluster widths" do
      UW.swidth(SpecHelper.cps('a'.ord, 0x4E00, 'b'.ord)).should eq(4)
    end

    it "skips controls under Skip" do
      UW.swidth(SpecHelper.cps('a'.ord, 0x1B, 'b'.ord), UW::CtrlPolicy::Skip).should eq(2)
    end

    it "fails the whole string under Fail" do
      UW.swidth(SpecHelper.cps('a'.ord, 0x1B, 'b'.ord), UW::CtrlPolicy::Fail).should eq(-1)
    end

    it "measures a plain ASCII string" do
      UW.swidth("hello").should eq(5)
    end

    it "counts each CJK char as width 2" do
      UW.swidth(SpecHelper.cps(0x4E00, 0x4E01, 0x4E02)).should eq(6)
    end

    it "counts a flag as width 2 in a string" do
      UW.swidth(SpecHelper.cps(0x1F1E6, 0x1F1E7)).should eq(2)
    end

    it "sums UTF-8 and UTF-32 paths identically for a mixed string" do
      s = "a\u00E9\u4E00\u{1F1E6}\u{1F1E7}"
      cps = Slice(UInt32).new(s.size) { 0_u32 }
      s.each_char_with_index { |ch, i| cps[i] = ch.ord.to_u32 }
      UW.swidth(s).should eq(UW.swidth(cps))
    end
  end
end
