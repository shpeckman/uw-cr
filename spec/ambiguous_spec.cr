# spec/ambiguous_spec.cr

require "./spec_helper"

private WIDE   = UW::WidthOpts.unicode.with_ambiguous_wide(true)
private LEGACY = UW::WidthOpts.legacy.with_ambiguous_wide(true)

describe UW do
  describe "ambiguous width, code point" do
    it "reports an ambiguous char as 1 by default" do
      UW.width_cp(0x00A7_u32).should eq(1)
    end

    it "reports an ambiguous char as 2 when ambiguous_wide is set" do
      UW.width_cp(0x00A7_u32, WIDE).should eq(2)
    end

    it "leaves a non-ambiguous narrow char at 1" do
      UW.width_cp(0x0078_u32, WIDE).should eq(1)
    end

    it "leaves an intrinsically wide char at 2" do
      UW.width_cp(0x4E00_u32, WIDE).should eq(2)
    end

    it "keeps a control char at -1" do
      UW.width_cp(0x1B_u32, WIDE).should eq(-1)
    end
  end

  describe "ambiguous width, strings" do
    it "sums ambiguous chars as wide when enabled" do
      UW.swidth("\u00A7\u00B1\u2103", opts: WIDE).should eq(6)
    end

    it "sums the same chars as narrow by default" do
      UW.swidth("\u00A7\u00B1\u2103").should eq(3)
    end

    it "mixes ambiguous and plain characters" do
      UW.swidth("a\u00A7b", opts: WIDE).should eq(4)
      UW.swidth("a\u00A7b").should eq(3)
    end

    it "applies in legacy mode as well" do
      UW.swidth("\u2190", opts: LEGACY).should eq(2)
      UW.swidth("\u2190", opts: UW::WidthOpts.legacy).should eq(1)
    end
  end

  describe "ambiguous width, clusters and truncation" do
    it "reports the promoted width per cluster" do
      widths = [] of Int32
      UW.clusters("\u00A7x", opts: WIDE).each { |sp| widths << sp.width }
      widths.should eq([2, 1])
    end

    it "never splits a promoted wide cluster across the budget" do
      w, off = UW.truncate("a\u00A7b", 2, opts: WIDE)
      w.should eq(1)
      off.should eq(1)
    end
  end
end
