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

    it "honours a runtime cap override above the default" do
      opts = UW::WidthOpts.new(UW::WidthMode::Unicode, 8)
      w, _ = UW.width(SpecHelper.cps(0x1F468, 0x200D, 0x1F469), opts)
      w.should eq(4)
    end

    it "disables capping when cap is zero" do
      opts = UW::WidthOpts.new(UW::WidthMode::Unicode, 0)
      w, _ = UW.width(SpecHelper.cps(0x1F468, 0x200D, 0x1F469), opts)
      w.should eq(4)
    end

    it "sums every member of a four-person family under a raised cap" do
      opts = UW::WidthOpts.new(UW::WidthMode::Unicode, 0)
      w, _ = UW.width(SpecHelper.cps(0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467, 0x200D, 0x1F466), opts)
      w.should eq(8)
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

  describe ".width (legacy mode)" do
    it "does not promote a narrow emoji base under VS16" do
      w, _ = UW.width(SpecHelper.cps(0x2764, 0xFE0F), UW::WidthOpts.legacy)
      w.should eq(1)
    end

    it "sums a ZWJ sequence per code point rather than coalescing" do
      w, _ = UW.width(SpecHelper.cps(0x1F468, 0x200D, 0x1F469), UW::WidthOpts.legacy)
      w.should eq(UW::CLUSTER_WIDTH_CAP)
    end

    it "sums a ZWJ sequence uncapped in legacy mode" do
      opts = UW::WidthOpts.new(UW::WidthMode::Legacy, 0)
      w, _ = UW.width(SpecHelper.cps(0x1F468, 0x200D, 0x1F469), opts)
      w.should eq(4)
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
      s   = "a\u00E9\u4E00\u{1F1E6}\u{1F1E7}"
      cps = Slice(UInt32).new(s.size) { 0_u32 }
      s.each_char_with_index { |ch, i| cps[i] = ch.ord.to_u32 }
      UW.swidth(s).should eq(UW.swidth(cps))
    end

    it "differs between unicode and legacy width for VS16 emoji" do
      s = "\u2764\uFE0F"
      UW.swidth(s, opts: UW::WidthOpts.unicode).should eq(2)
      UW.swidth(s, opts: UW::WidthOpts.legacy).should eq(1)
    end
  end

  describe ".truncate" do
    it "stops before a cluster that would overflow the budget" do
      w, off = UW.truncate(SpecHelper.cps('a'.ord, 0x4E00, 'b'.ord), 2)
      w.should eq(1)
      off.should eq(1)
    end

    it "fits an exact budget entirely" do
      w, off = UW.truncate(SpecHelper.cps('a'.ord, 0x4E00, 'b'.ord), 4)
      w.should eq(4)
      off.should eq(3)
    end

    it "never splits a wide cluster across the boundary" do
      w, off = UW.truncate(SpecHelper.cps(0x4E00, 0x4E01), 1)
      w.should eq(0)
      off.should eq(0)
    end

    it "returns zero for a non-positive budget" do
      UW.truncate(SpecHelper.cps('a'.ord), 0).should eq({0, 0})
    end

    it "reports byte offsets on the UTF-8 path" do
      w, off = UW.truncate("a\u4E00b", 2)
      w.should eq(1)
      off.should eq(1)
    end

    it "measures a wide flag against the budget as one unit" do
      w, off = UW.truncate(SpecHelper.cps(0x1F1E6, 0x1F1E7, 'x'.ord), 2)
      w.should eq(2)
      off.should eq(2)
    end
  end
end
