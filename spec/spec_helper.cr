# spec/spec_helper.cr

require "spec"
require "http/client"
require "file_utils"
require "../src/uw-cr"

module SpecHelper
  TEST_BASE_URL = "https://www.unicode.org/Public/#{UW.unicode_version}/ucd/auxiliary"

  record GraphemeCase,
    line    : Int32,
    cps     : Slice(UInt32),
    breaks  : Array(Bool),
    comment : String

  def self.cps(*values : Int) : Slice(UInt32)
    Slice(UInt32).new(values.size) { |i| values[i].to_u32 }
  end

  def self.grapheme_cases : Array(GraphemeCase)
    break_cases("GraphemeBreakTest.txt")
  end

  def self.line_cases : Array(GraphemeCase)
    break_cases("LineBreakTest.txt")
  end

  def self.cache_dir : String
    base = ENV["XDG_CACHE_HOME"]?
    base = "#{Path.home}/.cache" if base.nil? || base.empty?
    "#{base}/uw-cr/#{UW.unicode_version}"
  end

  def self.ensure_file(name : String) : String
    path = "#{cache_dir}/#{name}"
    return path if File.exists?(path)

    url  = "#{TEST_BASE_URL}/#{name}"
    body = HTTP::Client.get(url) do |resp|
      raise "GET #{url} -> #{resp.status_code}" unless resp.success?
      resp.body_io.gets_to_end
    end
    FileUtils.mkdir_p(cache_dir)
    File.write(path, body)
    path
  end

  def self.break_cases(file : String) : Array(GraphemeCase)
    path  = ensure_file(file)
    cases = [] of GraphemeCase
    File.read_lines(path).each_with_index do |raw, idx|
      body = raw
      if hash = body.index('#')
        comment = body[(hash + 1)..].strip
        body    = body[0...hash]
      else
        comment = ""
      end
      body = body.strip
      next if body.empty?

      tokens = body.split(/\s+/)
      cps    = [] of UInt32
      breaks = [] of Bool
      tokens.each do |tok|
        case tok
        when "\u00F7" then breaks << true
        when "\u00D7" then breaks << false
        else               cps << tok.to_u32(16)
        end
      end

      cases << GraphemeCase.new(
        line: idx + 1,
        cps: Slice(UInt32).new(cps.size) { |i| cps[i] },
        breaks: breaks,
        comment: comment,
      )
    end
    cases
  end
end
