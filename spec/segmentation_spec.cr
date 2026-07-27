# spec/segmentation_spec.cr

require "./spec_helper"

private def cluster_count(cps : Slice(UInt32)) : Int32
  st = UW::State.new
  n = 0
  cps.each { |cp| n += 1 if st.grapheme_break(cp) }
  n
end

describe UW::State do
  describe "Unicode GraphemeBreakTest.txt (17.0.0)" do
    cases = SpecHelper.grapheme_cases

    it "loads the official test cases" do
      cases.size.should be > 700
    end

    it "produces the exact break at every position for all cases" do
      failures = [] of String
      cases.each do |c|
        st = UW::State.new
        c.cps.each_with_index do |cp, i|
          got = st.grapheme_break(cp)
          want = c.breaks[i]
          if got != want
            failures << "line #{c.line} pos #{i}: got #{got}, want #{want} | #{c.comment}"
          end
        end
      end
      failures.should be_empty
    end

    it "has a trailing break implied after every case" do
      cases.each { |c| c.breaks.last.should be_true }
    end
  end

  describe "targeted rule cases" do
    it "always breaks before the first codepoint (GB1)" do
      UW::State.new.grapheme_break('A'.ord.to_u32).should be_true
    end

    it "does not break within CR LF (GB3)" do
      cluster_count(SpecHelper.cps(0x0D, 0x0A)).should eq(1)
    end

    it "breaks around other controls (GB4/GB5)" do
      cluster_count(SpecHelper.cps('A'.ord, 0x0A, 'B'.ord)).should eq(3)
    end

    it "keeps Hangul L V T together (GB6/7/8)" do
      cluster_count(SpecHelper.cps(0x1100, 0x1161, 0x11A8)).should eq(1)
    end

    it "does not break before Extend or ZWJ (GB9)" do
      cluster_count(SpecHelper.cps('e'.ord, 0x0301)).should eq(1)
    end

    it "does not break before SpacingMark (GB9a)" do
      cluster_count(SpecHelper.cps(0x0915, 0x093E)).should eq(1)
    end

    it "does not break after Prepend (GB9b)" do
      cluster_count(SpecHelper.cps(0x0600, 0x0627)).should eq(1)
    end

    it "keeps Indic conjunct consonant-linker-consonant together (GB9c)" do
      cluster_count(SpecHelper.cps(0x0915, 0x094D, 0x0915)).should eq(1)
    end

    it "keeps emoji ZWJ sequences together (GB11)" do
      cluster_count(SpecHelper.cps(0x1F468, 0x200D, 0x1F469)).should eq(1)
    end

    it "does not join non-pictographic across ZWJ" do
      cluster_count(SpecHelper.cps('a'.ord, 0x200D, 'b'.ord)).should eq(2)
    end

    it "pairs regional indicators (GB12/13)" do
      cluster_count(SpecHelper.cps(0x1F1E6, 0x1F1E7)).should eq(1)
    end

    it "breaks a run of four regional indicators into two flags" do
      cluster_count(SpecHelper.cps(0x1F1E6, 0x1F1E7, 0x1F1E8, 0x1F1E9)).should eq(2)
    end

    it "breaks by default between unrelated codepoints (GB999)" do
      cluster_count(SpecHelper.cps('a'.ord, 'b'.ord)).should eq(2)
    end

    it "reset restores initial state" do
      st = UW::State.new
      st.grapheme_break(0x1F1E6_u32)
      st.reset
      st.grapheme_break(0x1F1E7_u32).should be_true
    end
  end
end
