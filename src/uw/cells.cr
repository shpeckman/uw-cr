# src/uw/cells.cr

module UW
  record Cell, offset : Int32, size : Int32, width : Int32, col : Int32, kind : SpanKind = SpanKind::Graphemic

  struct Utf32Cells
    def initialize(@cps : Slice(UInt32), @opts : WidthOpts = WidthOpts.unicode)
      @it  = Utf32Clusters.new(@cps, @opts)
      @off = 0
      @col = 0
    end

    def reset(cps : Slice(UInt32), opts : WidthOpts = @opts) : Nil
      @cps = cps
      @opts = opts
      @it.reset(cps, opts)
      @off = 0
      @col = 0
    end

    def next? : Cell?
      span = @it.next?
      return nil unless span
      w    = span.width < 0 ? 0 : span.width
      cell = Cell.new(@off, span.size, span.width, @col, span.kind)
      @off += span.size
      @col += w
      cell
    end

    def each(& : Cell ->) : Nil
      while cell = next?
        yield cell
      end
    end
  end

  struct Utf8Cells
    def initialize(@bytes : Bytes, @policy : Utf8Policy = Utf8Policy::Replace, @opts : WidthOpts = WidthOpts.unicode)
      @it  = Utf8Clusters.new(@bytes, @policy, @opts)
      @off = 0
      @col = 0
    end

    def reset(bytes : Bytes, policy : Utf8Policy = @policy, opts : WidthOpts = @opts) : Nil
      @bytes = bytes
      @policy = policy
      @opts = opts
      @it.reset(bytes, policy, opts)
      @off = 0
      @col = 0
    end

    def reset(s : String, policy : Utf8Policy = @policy, opts : WidthOpts = @opts) : Nil
      reset(s.to_slice, policy, opts)
    end

    def next? : Cell?
      span = @it.next?
      return nil unless span
      w    = span.width < 0 ? 0 : span.width
      cell = Cell.new(@off, span.size, span.width, @col, span.kind)
      @off += span.size
      @col += w
      cell
    end

    def each(& : Cell ->) : Nil
      while cell = next?
        yield cell
      end
    end
  end

  def self.cells(cps : Slice(UInt32), opts : WidthOpts = WidthOpts.unicode) : Utf32Cells
    Utf32Cells.new(cps, opts)
  end

  def self.cells(s : Bytes, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : Utf8Cells
    Utf8Cells.new(s, policy, opts)
  end

  def self.cells(s : String, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : Utf8Cells
    Utf8Cells.new(s.to_slice, policy, opts)
  end

  def self.offset_to_col(cps : Slice(UInt32), offset : Int32, opts : WidthOpts = WidthOpts.unicode) : Int32
    return 0 if offset <= 0
    col = 0
    Utf32Cells.new(cps, opts).each do |cell|
      break if cell.offset >= offset
      col = cell.col + (cell.width < 0 ? 0 : cell.width)
    end
    col
  end

  def self.offset_to_col(s : Bytes, offset : Int32, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : Int32
    return 0 if offset <= 0
    col = 0
    Utf8Cells.new(s, policy, opts).each do |cell|
      break if cell.offset >= offset
      col = cell.col + (cell.width < 0 ? 0 : cell.width)
    end
    col
  end

  def self.offset_to_col(s : String, offset : Int32, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : Int32
    offset_to_col(s.to_slice, offset, policy, opts)
  end

  def self.col_to_offset(cps : Slice(UInt32), col : Int32, opts : WidthOpts = WidthOpts.unicode) : Int32
    return 0 if col <= 0
    last = 0
    Utf32Cells.new(cps, opts).each do |cell|
      return cell.offset if cell.col >= col
      last = cell.offset + cell.size
    end
    last
  end

  def self.col_to_offset(s : Bytes, col : Int32, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : Int32
    return 0 if col <= 0
    last = 0
    Utf8Cells.new(s, policy, opts).each do |cell|
      return cell.offset if cell.col >= col
      last = cell.offset + cell.size
    end
    last
  end

  def self.col_to_offset(s : String, col : Int32, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : Int32
    col_to_offset(s.to_slice, col, policy, opts)
  end

  def self.next_grapheme(cps : Slice(UInt32), offset : Int32) : Int32
    return 0 if offset < 0
    return cps.size if offset >= cps.size
    offset + grapheme_next(cps[offset, cps.size - offset])
  end

  def self.next_grapheme(s : Bytes, offset : Int32, policy : Utf8Policy = Utf8Policy::Replace) : Int32
    return 0 if offset < 0
    return s.size if offset >= s.size
    offset + grapheme_next(s[offset, s.size - offset], policy)
  end

  def self.next_grapheme(s : String, offset : Int32, policy : Utf8Policy = Utf8Policy::Replace) : Int32
    next_grapheme(s.to_slice, offset, policy)
  end

  def self.prev_grapheme(cps : Slice(UInt32), offset : Int32) : Int32
    return 0 if offset <= 0
    limit = offset > cps.size ? cps.size : offset
    prev  = 0
    off   = 0
    while off < limit
      step = grapheme_next(cps[off, cps.size - off])
      break if step <= 0
      break if off + step >= limit
      prev = off + step
      off += step
    end
    prev
  end

  def self.prev_grapheme(s : Bytes, offset : Int32, policy : Utf8Policy = Utf8Policy::Replace) : Int32
    return 0 if offset <= 0
    limit = offset > s.size ? s.size : offset
    prev  = 0
    off   = 0
    while off < limit
      step = grapheme_next(s[off, s.size - off], policy)
      break if step <= 0
      break if off + step >= limit
      prev = off + step
      off += step
    end
    prev
  end

  def self.prev_grapheme(s : String, offset : Int32, policy : Utf8Policy = Utf8Policy::Replace) : Int32
    prev_grapheme(s.to_slice, offset, policy)
  end

  record ColSlice, offset : Int32, size : Int32, start_col : Int32, end_col : Int32, pad_left : Int32, pad_right : Int32

  def self.slice_cols(cps : Slice(UInt32), start_col : Int32, end_col : Int32, opts : WidthOpts = WidthOpts.unicode) : ColSlice
    slice_cols_impl(Utf32Cells.new(cps, opts), start_col, end_col)
  end

  def self.slice_cols(s : Bytes, start_col : Int32, end_col : Int32, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : ColSlice
    slice_cols_impl(Utf8Cells.new(s, policy, opts), start_col, end_col)
  end

  def self.slice_cols(s : String, start_col : Int32, end_col : Int32, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : ColSlice
    slice_cols(s.to_slice, start_col, end_col, policy, opts)
  end

  private def self.slice_cols_impl(it, start_col : Int32, end_col : Int32) : ColSlice
    lo = start_col < 0 ? 0 : start_col
    hi = end_col
    if hi <= lo
      return ColSlice.new(0, 0, lo, lo, 0, 0)
    end

    seg_off   = -1
    seg_end   = 0
    pad_left  = 0
    pad_right = 0

    while cell = it.next?
      w    = cell.width < 0 ? 0 : cell.width
      c_lo = cell.col
      c_hi = cell.col + w
      next if c_hi <= lo
      break if c_lo >= hi

      straddle_left  = c_lo < lo
      straddle_right = c_hi > hi

      if straddle_left
        visible = (c_hi < hi ? c_hi : hi) - lo
        pad_left += visible
        next
      end

      if straddle_right
        pad_right += hi - c_lo
        break
      end

      if seg_off < 0
        seg_off = cell.offset
      end
      seg_end = cell.offset + cell.size
    end

    if seg_off < 0
      return ColSlice.new(0, 0, lo, hi, pad_left, pad_right)
    end
    ColSlice.new(seg_off, seg_end - seg_off, lo, hi, pad_left, pad_right)
  end
end