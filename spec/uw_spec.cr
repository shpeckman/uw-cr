# spec/uw_spec.cr

require "spec"
require "../src/uw-cr"

describe Uw do
  it "reports the unicode version" do
    Uw.unicode_version.should eq("17.0.0")
  end

  it "reports the active width cap" do
    Uw.active_width_cap.should eq(2)
  end

  describe ".width" do
    it "measures ascii as 1" do
      Uw.width('A').should eq(1)
    end

    it "measures wide CJK as 2" do
      Uw.width('世').should eq(2)
    end

    it "measures a combining mark as 0" do
      Uw.width(0x0301).should eq(0)
    end

    it "returns nil for a control code" do
      Uw.width(0x07).should be_nil
    end
  end

  describe ".string_width" do
    it "sums plain ascii" do
      Uw.string_width("hello").should eq(5)
    end

    it "sums mixed width" do
      Uw.string_width("a世b").should eq(4)
    end

    it "treats a flag as a single 2-wide cluster" do
      Uw.string_width("🇯🇵").should eq(2)
    end

    it "caps a wide ZWJ sequence at the compiled cap" do
      Uw.string_width("👨‍👩‍👧").should eq(Uw.active_width_cap)
    end

    it "skips controls by default" do
      Uw.string_width("a\ab").should eq(2)
    end

    it "returns nil under Control::Fail when a control is present" do
      Uw.string_width("a\ab", Uw::Control::Fail).should be_nil
    end
  end

  describe ".graphemes" do
    it "splits combining sequences into single clusters" do
      Uw.graphemes("e\u0301x").should eq(["e\u0301", "x"])
    end

    it "keeps a flag as one grapheme" do
      Uw.graphemes("🇯🇵!").should eq(["🇯🇵", "!"])
    end
  end

  describe ".first_cluster_width" do
    it "measures the first cluster and reports bytes consumed" do
      w, consumed = Uw.first_cluster_width("世x")
      w.should eq(2)
      consumed.should eq("世".bytesize)
    end
  end

  describe ".next_grapheme_size" do
    it "returns byte length of the leading grapheme" do
      Uw.next_grapheme_size("e\u0301x").should eq("e\u0301".bytesize)
    end

    it "returns 0 for empty input" do
      Uw.next_grapheme_size("").should eq(0)
    end
  end

  describe Uw::Segmenter do
    it "detects boundaries across a stream" do
      seg = Uw::Segmenter.new
      # 'e' then combining acute then 'x': boundary before e, none before
      # the accent, boundary before x.
      seg.break_before?('e').should be_true
      seg.break_before?(0x0301).should be_false
      seg.break_before?('x').should be_true
    end
  end

  describe Uw::ClusterWidth do
    it "accumulates a cluster width" do
      cw = Uw::ClusterWidth.new
      cw.push('世')
      cw.width.should eq(2)
    end

    it "reports nil for a control cluster" do
      cw = Uw::ClusterWidth.new
      cw.push(0x07)
      cw.width.should be_nil
    end
  end

  describe "code-point slice API" do
    it "measures a UInt32 slice" do
      cps = Slice[0x61_u32, 0x4E16_u32, 0x62_u32]
      Uw.string_width(cps).should eq(4)
    end
  end
end