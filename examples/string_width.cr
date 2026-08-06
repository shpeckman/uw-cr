# examples/string_width.cr
require "uw-cr"

samples = {
  "héllo"                          => "combining marks",
  "a\u4E00b"                       => "narrow + wide CJK + narrow",
  "\u{1F468}\u200D\u{1F469}"       => "emoji ZWJ sequence",
  "\u{1F1E6}\u{1F1E7}"             => "regional-indicator flag",
  "a\tb"                           => "embedded tab (control)",
}

samples.each do |text, label|
  skip = UW.swidth(text, ctrl: UW::CtrlPolicy::Skip)
  fail = UW.swidth(text, ctrl: UW::CtrlPolicy::Fail)
  puts "#{label.ljust(28)} skip=#{skip}  fail=#{fail}"
end
