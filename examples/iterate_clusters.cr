# examples/iterate_clusters.cr
require "uw-cr"

def clusters(text : String) : Array(Tuple(String, Int32))
  bytes = text.to_slice
  out = [] of Tuple(String, Int32)
  offset = 0
  while offset < bytes.size
    w, n = UW.width(bytes[offset, bytes.size - offset])
    break if n == 0
    out << {String.new(bytes[offset, n]), w}
    offset += n
  end
  out
end

clusters("a\u0301🇦🇧🚀").each do |grapheme, width|
  puts "#{grapheme.inspect.ljust(14)} width=#{width}"
end
