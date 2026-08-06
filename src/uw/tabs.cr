# src/uw/tabs.cr

module UW
  DEFAULT_TAB_SIZE = 8

  @[AlwaysInline]
  def self.tab_width(col : Int32, tab_size : Int32 = DEFAULT_TAB_SIZE) : Int32
    return 0 if tab_size <= 0
    c = col < 0 ? 0 : col
    tab_size - (c % tab_size)
  end

  @[AlwaysInline]
  def self.next_tab_stop(col : Int32, tab_size : Int32 = DEFAULT_TAB_SIZE) : Int32
    return col if tab_size <= 0
    col + tab_width(col, tab_size)
  end

  def self.swidth_tabs(s : String, tab_size : Int32 = DEFAULT_TAB_SIZE, start_col : Int32 = 0, opts : WidthOpts = WidthOpts.unicode) : Int32
    swidth_tabs(s.to_slice, tab_size, start_col, Utf8Policy::Replace, opts)
  end

  def self.swidth_tabs(s : Bytes, tab_size : Int32 = DEFAULT_TAB_SIZE, start_col : Int32 = 0, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : Int32
    col = start_col < 0 ? 0 : start_col
    Utf8Cells.new(s, policy, opts).each do |cell|
      if cell.kind.tab?
        col = next_tab_stop(col, tab_size)
      elsif cell.width > 0
        col += cell.width
      end
    end
    col - (start_col < 0 ? 0 : start_col)
  end

  def self.swidth_tabs(cps : Slice(UInt32), tab_size : Int32 = DEFAULT_TAB_SIZE, start_col : Int32 = 0, opts : WidthOpts = WidthOpts.unicode) : Int32
    col = start_col < 0 ? 0 : start_col
    Utf32Cells.new(cps, opts).each do |cell|
      if cell.kind.tab?
        col = next_tab_stop(col, tab_size)
      elsif cell.width > 0
        col += cell.width
      end
    end
    col - (start_col < 0 ? 0 : start_col)
  end

  def self.expand_tabs(s : String, tab_size : Int32 = DEFAULT_TAB_SIZE, start_col : Int32 = 0, opts : WidthOpts = WidthOpts.unicode) : String
    bytes = s.to_slice
    col   = start_col < 0 ? 0 : start_col
    ptr   = bytes.to_unsafe
    String.build do |io|
      Utf8Cells.new(bytes, Utf8Policy::Replace, opts).each do |cell|
        case cell.kind
        when .tab?
          n = tab_width(col, tab_size)
          n.times { io << ' ' }
          col += n
        when .lf?, .cr?, .crlf?
          io.write(bytes[cell.offset, cell.size])
          col = 0
        else
          io.write(bytes[cell.offset, cell.size])
          col += cell.width if cell.width > 0
        end
      end
    end
  end
end
