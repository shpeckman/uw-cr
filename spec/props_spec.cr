# spec/props_spec.cr

require "./spec_helper"

describe UW do
  describe ".unicode_version" do
    it "is 17.0.0" do
      UW.unicode_version.should eq("17.0.0")
    end
  end

  describe ".width_cp" do
    it "returns 0 above the trie range" do
      UW.width_cp(0x110000_u32).should eq(0)
      UW.width_cp(0xFFFFFFFF_u32).should eq(0)
    end

    it "is 1 for ASCII letters" do
      UW.width_cp('A'.ord.to_u32).should eq(1)
    end

    it "is 1 for the space character" do
      UW.width_cp(' '.ord.to_u32).should eq(1)
    end

    it "is -1 for C0 controls" do
      UW.width_cp(0x00_u32).should eq(-1)
      UW.width_cp(0x1B_u32).should eq(-1)
      UW.width_cp(0x7F_u32).should eq(-1)
    end

    it "is 0 for combining marks" do
      UW.width_cp(0x0301_u32).should eq(0)
      UW.width_cp(0x0308_u32).should eq(0)
    end

    it "is 2 for wide CJK ideographs" do
      UW.width_cp(0x4E00_u32).should eq(2)
      UW.width_cp(0x6F22_u32).should eq(2)
    end

    it "is 2 for wide Hangul syllables" do
      UW.width_cp(0xAC00_u32).should eq(2)
    end

    it "is 2 for default-emoji-presentation codepoints" do
      UW.width_cp(0x1F600_u32).should eq(2)
    end

    it "is 0 for the zero-width joiner" do
      UW.width_cp(0x200D_u32).should eq(0)
    end
  end
end
