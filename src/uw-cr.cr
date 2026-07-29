# src/uw-cr.cr

module UW
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end

require "./uw"
