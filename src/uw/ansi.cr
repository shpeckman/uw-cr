# src/uw/ansi.cr

module UW
  module Ansi
    ESC = 0x1B_u8
    BEL = 0x07_u8

    enum ChunkKind
      Text = 0
      Csi  = 1
      Osc  = 2
      Esc  = 3
    end

    record Chunk, kind : ChunkKind, offset : Int32, size : Int32

    struct Scanner
      def initialize(@bytes : Bytes)
        @ptr = @bytes.to_unsafe
        @n   = @bytes.size
        @i   = 0
      end

      def reset(bytes : Bytes) : Nil
        @bytes = bytes
        @ptr   = bytes.to_unsafe
        @n     = bytes.size
        @i     = 0
      end

      def next? : Chunk?
        return nil if @i >= @n
        start = @i

        if @ptr[@i] == ESC
          return scan_escape(start)
        end

        while @i < @n && @ptr[@i] != ESC
          @i += 1
        end
        Chunk.new(ChunkKind::Text, start, @i - start)
      end

      private def scan_escape(start : Int32) : Chunk
        if @i + 1 >= @n
          @i = @n
          return Chunk.new(ChunkKind::Esc, start, @i - start)
        end

        nb = @ptr[@i + 1]
        if nb == 0x5B_u8
          return scan_csi(start)
        elsif nb == 0x5D_u8
          return scan_osc(start)
        elsif nb == 0x50_u8 || nb == 0x58_u8 || nb == 0x5E_u8 || nb == 0x5F_u8
          return scan_st_string(start)
        else
          @i += 2
          Chunk.new(ChunkKind::Esc, start, @i - start)
        end
      end

      private def scan_csi(start : Int32) : Chunk
        @i += 2
        while @i < @n
          b = @ptr[@i]
          @i += 1
          break if b >= 0x40_u8 && b <= 0x7E_u8
        end
        Chunk.new(ChunkKind::Csi, start, @i - start)
      end

      private def scan_osc(start : Int32) : Chunk
        @i += 2
        while @i < @n
          b = @ptr[@i]
          if b == BEL
            @i += 1
            break
          elsif b == ESC && @i + 1 < @n && @ptr[@i + 1] == 0x5C_u8
            @i += 2
            break
          end
          @i += 1
        end
        Chunk.new(ChunkKind::Osc, start, @i - start)
      end

      private def scan_st_string(start : Int32) : Chunk
        @i += 2
        while @i < @n
          b = @ptr[@i]
          if b == BEL
            @i += 1
            break
          elsif b == ESC && @i + 1 < @n && @ptr[@i + 1] == 0x5C_u8
            @i += 2
            break
          end
          @i += 1
        end
        Chunk.new(ChunkKind::Esc, start, @i - start)
      end

      def each(& : Chunk ->) : Nil
        while chunk = next?
          yield chunk
        end
      end
    end

    def self.strip(s : String) : String
      strip(s.to_slice)
    end

    def self.strip(bytes : Bytes) : String
      String.build do |io|
        Scanner.new(bytes).each do |chunk|
          io.write(bytes[chunk.offset, chunk.size]) if chunk.kind.text?
        end
      end
    end

    def self.swidth(s : String, ctrl : CtrlPolicy = CtrlPolicy::Skip, opts : WidthOpts = WidthOpts.unicode) : Int32
      swidth(s.to_slice, ctrl, opts)
    end

    def self.swidth(bytes : Bytes, ctrl : CtrlPolicy = CtrlPolicy::Skip, opts : WidthOpts = WidthOpts.unicode) : Int32
      total = 0
      Scanner.new(bytes).each do |chunk|
        next unless chunk.kind.text?
        w = UW.swidth(bytes[chunk.offset, chunk.size], Utf8Policy::Replace, ctrl, opts)
        return -1 if w < 0 && ctrl.fail?
        total += w if w > 0
      end
      total
    end

    class SgrState
      def initialize
        @active = false
        @seq    = Bytes.empty
      end

      def reset : Nil
        @active = false
        @seq    = Bytes.empty
      end

      def active? : Bool
        @active
      end

      def observe(bytes : Bytes, chunk : Chunk) : Nil
        return unless chunk.kind.csi?
        return if chunk.size < 3
        final = bytes[chunk.offset + chunk.size - 1]
        return unless final == 0x6D_u8

        body_off = chunk.offset + 2
        body_len = chunk.size - 3
        if body_len <= 0 || sgr_is_reset(bytes, body_off, body_len)
          @active = false
          @seq    = Bytes.empty
        else
          @active = true
          @seq    = bytes[chunk.offset, chunk.size]
        end
      end

      def prefix : Bytes
        @seq
      end

      private def sgr_is_reset(bytes : Bytes, off : Int32, len : Int32) : Bool
        return true if len == 1 && bytes[off] == 0x30_u8
        false
      end
    end

    RESET_SGR = Bytes[0x1B_u8, 0x5B_u8, 0x30_u8, 0x6D_u8]

    def self.truncate(s : String, max_cols : Int32, ellipsis : String = "", opts : WidthOpts = WidthOpts.unicode) : String
      truncate(s.to_slice, max_cols, ellipsis, opts)
    end

    def self.truncate(bytes : Bytes, max_cols : Int32, ellipsis : String = "", opts : WidthOpts = WidthOpts.unicode) : String
      return "" if max_cols <= 0

      total = swidth(bytes, opts: opts)
      if total <= max_cols
        return String.new(bytes)
      end

      ell_w  = ellipsis.empty? ? 0 : UW.swidth(ellipsis, opts: opts)
      budget = max_cols - ell_w
      budget = 0 if budget < 0

      sgr = SgrState.new
      col = 0
      io  = IO::Memory.new
      done = false

      Scanner.new(bytes).each do |chunk|
        break if done
        case chunk.kind
        when .text?
          seg = bytes[chunk.offset, chunk.size]
          w   = UW.swidth(seg, opts: opts)
          if col + w <= budget
            io.write(seg)
            col += w
          else
            room = budget - col
            _, cut = UW.truncate(seg, room, opts: opts)
            io.write(seg[0, cut]) if cut > 0
            done = true
          end
        else
          io.write(bytes[chunk.offset, chunk.size])
          sgr.observe(bytes, chunk)
        end
      end

      io.write(ellipsis.to_slice) unless ellipsis.empty?
      io.write(RESET_SGR) if sgr.active?
      String.new(io.to_slice)
    end

    def self.pad(s : String, cols : Int32, align : Align = Align::Left, fill : Char = ' ', opts : WidthOpts = WidthOpts.unicode) : String
      w = swidth(s, opts: opts)
      return s if w >= cols
      deficit = cols - w
      fw      = UW.width_cp(fill.ord.to_u32, opts)
      fw      = 1 if fw <= 0
      run = ->(count : Int32) do
        String.build do |io|
          n = count // fw
          n.times { io << fill }
          (count - n * fw).times { io << ' ' }
        end
      end
      case align
      in Align::Left
        s + run.call(deficit)
      in Align::Right
        run.call(deficit) + s
      in Align::Center
        left = deficit // 2
        run.call(left) + s + run.call(deficit - left)
      end
    end

    def self.fit(s : String, cols : Int32, ellipsis : String = "\u2026", opts : WidthOpts = WidthOpts.unicode) : String
      truncate(s, cols, ellipsis, opts)
    end

    record WrapLine, text : String, width : Int32, mandatory : Bool

    def self.wrap(s : String, cols : Int32, opts : WrapOpts = WrapOpts.new) : Array(WrapLine)
      wrap(s.to_slice, cols, opts)
    end

    def self.wrap(bytes : Bytes, cols : Int32, opts : WrapOpts = WrapOpts.new) : Array(WrapLine)
      plain_io = IO::Memory.new
      map      = [] of Int32
      esc_at   = {} of Int32 => Bytes
      order    = [] of Int32

      Scanner.new(bytes).each do |chunk|
        if chunk.kind.text?
          seg = bytes[chunk.offset, chunk.size]
          i   = 0
          while i < seg.size
            map << plain_io.size
            plain_io.write_byte(seg[i])
            i += 1
          end
        else
          key = plain_io.size
          existing = esc_at[key]?
          combined = existing ? combine(existing, bytes[chunk.offset, chunk.size]) : bytes[chunk.offset, chunk.size]
          esc_at[key] = combined
          order << key unless existing
        end
      end
      map << plain_io.size

      plain    = plain_io.to_slice
      esc_keys = order.sort
      lines    = [] of WrapLine

      sgr        = SgrState.new
      esc_cursor = 0

      wrapper = Utf8Wrap.new(plain, cols, Utf8Policy::Replace, opts)
      wrapper.each do |line|
        lo = line.offset
        hi = line.offset + line.size

        while esc_cursor < esc_keys.size && esc_keys[esc_cursor] < lo
          scan_sgr_into(sgr, esc_at[esc_keys[esc_cursor]])
          esc_cursor += 1
        end

        io = IO::Memory.new
        io.write(sgr.prefix) if sgr.active?

        pos = lo
        while pos < hi
          while esc_cursor < esc_keys.size && esc_keys[esc_cursor] == pos
            k = esc_at[esc_keys[esc_cursor]]
            io.write(k)
            scan_sgr_into(sgr, k)
            esc_cursor += 1
          end
          io.write_byte(plain[pos])
          pos += 1
        end

        io.write(RESET_SGR) if sgr.active?
        lines << WrapLine.new(String.new(io.to_slice), line.width, line.mandatory)
      end

      while esc_cursor < esc_keys.size
        scan_sgr_into(sgr, esc_at[esc_keys[esc_cursor]])
        esc_cursor += 1
      end

      lines
    end

    private def self.combine(a : Bytes, b : Bytes) : Bytes
      buf = Bytes.new(a.size + b.size)
      a.copy_to(buf)
      b.copy_to(buf + a.size)
      buf
    end

    private def self.scan_sgr_into(sgr : SgrState, esc : Bytes) : Nil
      Scanner.new(esc).each do |chunk|
        sgr.observe(esc, chunk)
      end
    end
  end
end
