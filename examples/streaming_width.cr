# examples/streaming_width.cr
require "uw-cr"

def stream_width(chunks : Array(String)) : Int32
  st = UW::State.new
  cl = UW::Cluster.new
  total = 0

  chunks.each do |chunk|
    chunk.each_char do |ch|
      cp = ch.ord.to_u32
      if st.grapheme_break(cp) && cl.started
        total += cl.display_width
        cl.reset
      end
      cl.push(cp)
    end
  end

  total += cl.display_width if cl.started
  total
end

# The combining acute is split across a chunk boundary, but a persistent
# State segments it as one cluster with the "e".
puts stream_width(["e", "\u0301", "a\u4E00"])  # => 3
