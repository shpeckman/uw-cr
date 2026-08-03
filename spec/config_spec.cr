# spec/config_spec.cr

require "./spec_helper"

describe UW::Config do
  it "defaults to legacy width when 2027 is unknown" do
    cfg = UW::Config.new
    cfg.grapheme_processing?.should be_false
    cfg.width_mode.should eq(UW::WidthMode::Legacy)
  end

  it "selects unicode width when 2027 is supported and set" do
    cfg = UW::Config.new(supported: true, state: UW::Mode2027State::Set)
    cfg.grapheme_processing?.should be_true
    cfg.width_mode.should eq(UW::WidthMode::Unicode)
  end

  it "selects unicode width when permanently set" do
    cfg = UW::Config.new(supported: true, state: UW::Mode2027State::PermanentlySet)
    cfg.width_mode.should eq(UW::WidthMode::Unicode)
  end

  it "stays legacy when supported but reset" do
    cfg = UW::Config.new(supported: true, state: UW::Mode2027State::Reset)
    cfg.width_mode.should eq(UW::WidthMode::Legacy)
  end

  it "ignores state when unsupported" do
    cfg = UW::Config.new(supported: false, state: UW::Mode2027State::Set)
    cfg.grapheme_processing?.should be_false
  end

  it "produces opts carrying the resolved mode and given cap" do
    cfg  = UW::Config.new(supported: true, state: UW::Mode2027State::Set)
    opts = cfg.opts(4)
    opts.mode.should eq(UW::WidthMode::Unicode)
    opts.cap.should eq(4)
  end

  it "drives swidth through the resolved mode" do
    on  = UW::Config.new(supported: true, state: UW::Mode2027State::Set)
    off = UW::Config.new(supported: true, state: UW::Mode2027State::Reset)
    s   = "\u2764\uFE0F"
    UW.swidth(s, opts: on.opts).should eq(2)
    UW.swidth(s, opts: off.opts).should eq(1)
  end
end
