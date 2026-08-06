# examples/align_table.cr
require "uw-cr"

def pad(text : String, width : Int32) : String
  fill = width - UW.swidth(text)
  fill > 0 ? text + " " * fill : text
end

rows = [
  {"名前", "Alice"},
  {"café", "42"},
  {"emoji 🚀", "go"},
  {"plain", "x"},
]

col = rows.max_of { |left, _| UW.swidth(left) }

rows.each do |left, right|
  puts "#{pad(left, col)} | #{right}"
end
