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

    enum SgrColorKind
      Default = 0
      Palette = 1
      Rgb     = 2
    end

    struct SgrColor
      getter kind : SgrColorKind
      getter idx  : UInt8
      getter r    : UInt8
      getter g    : UInt8
      getter b    : UInt8

      def initialize(@kind : SgrColorKind = SgrColorKind::Default, @idx : UInt8 = 0_u8, @r : UInt8 = 0_u8, @g : UInt8 = 0_u8, @b : UInt8 = 0_u8)
      end

      def self.default : SgrColor
        new
      end

      def self.palette(idx : UInt8) : SgrColor
        new(SgrColorKind::Palette, idx)
      end

      def self.rgb(r : UInt8, g : UInt8, b : UInt8) : SgrColor
        new(SgrColorKind::Rgb, 0_u8, r, g, b)
      end

      def default? : Bool
        @kind.default?
      end

      def ==(other : SgrColor) : Bool
        return false unless @kind == other.kind
        case @kind
        in SgrColorKind::Default then true
        in SgrColorKind::Palette then @idx == other.idx
        in SgrColorKind::Rgb     then @r == other.r && @g == other.g && @b == other.b
        end
      end
    end

    class SgrState
      UNDERLINE_NONE   = 0_u8
      UNDERLINE_SINGLE = 1_u8
      UNDERLINE_DOUBLE = 2_u8
      UNDERLINE_CURLY  = 3_u8
      UNDERLINE_DOTTED = 4_u8
      UNDERLINE_DASHED = 5_u8

      INTENSITY_NORMAL = 0_u8
      INTENSITY_BOLD   = 1_u8
      INTENSITY_FAINT  = 2_u8

      SCRIPT_NONE  = 0_u8
      SCRIPT_SUPER = 1_u8
      SCRIPT_SUB   = 2_u8

      property intensity : UInt8
      property italic    : Bool
      property underline : UInt8
      property blink     : UInt8
      property reverse   : Bool
      property conceal   : Bool
      property strike    : Bool
      property overline  : Bool
      property script    : UInt8
      property fg        : SgrColor
      property bg        : SgrColor
      property ul_color  : SgrColor

      def initialize
        @intensity = INTENSITY_NORMAL
        @italic    = false
        @underline = UNDERLINE_NONE
        @blink     = 0_u8
        @reverse   = false
        @conceal   = false
        @strike    = false
        @overline  = false
        @script    = SCRIPT_NONE
        @fg        = SgrColor.default
        @bg        = SgrColor.default
        @ul_color  = SgrColor.default
      end

      def reset : Nil
        @intensity = INTENSITY_NORMAL
        @italic    = false
        @underline = UNDERLINE_NONE
        @blink     = 0_u8
        @reverse   = false
        @conceal   = false
        @strike    = false
        @overline  = false
        @script    = SCRIPT_NONE
        @fg        = SgrColor.default
        @bg        = SgrColor.default
        @ul_color  = SgrColor.default
      end

      def active? : Bool
        @intensity != INTENSITY_NORMAL ||
          @italic ||
          @underline != UNDERLINE_NONE ||
          @blink != 0_u8 ||
          @reverse ||
          @conceal ||
          @strike ||
          @overline ||
          @script != SCRIPT_NONE ||
          !@fg.default? ||
          !@bg.default? ||
          !@ul_color.default?
      end

      def observe(bytes : Bytes, chunk : Chunk) : Nil
        return unless chunk.kind.csi?
        return if chunk.size < 3
        final = bytes[chunk.offset + chunk.size - 1]
        return unless final == 0x6D_u8

        params = parse_params(bytes, chunk.offset + 2, chunk.size - 3)
        apply(params)
      end

      def prefix : Bytes
        return Bytes.empty unless active?
        io = IO::Memory.new
        emit(io)
        io.to_slice
      end

      def emit(io : IO) : Nil
        return unless active?
        io.write_byte(ESC)
        io.write_byte(0x5B_u8)
        first = true

        case @intensity
        when INTENSITY_BOLD  then first = put(io, first, "1")
        when INTENSITY_FAINT then first = put(io, first, "2")
        end
        first = put(io, first, "3") if @italic

        case @underline
        when UNDERLINE_SINGLE then first = put(io, first, "4")
        when UNDERLINE_DOUBLE then first = put(io, first, "21")
        when UNDERLINE_CURLY  then first = put(io, first, "4:3")
        when UNDERLINE_DOTTED then first = put(io, first, "4:4")
        when UNDERLINE_DASHED then first = put(io, first, "4:5")
        end

        case @blink
        when 1_u8 then first = put(io, first, "5")
        when 2_u8 then first = put(io, first, "6")
        end

        first = put(io, first, "7") if @reverse
        first = put(io, first, "8") if @conceal
        first = put(io, first, "9") if @strike
        first = put(io, first, "53") if @overline

        case @script
        when SCRIPT_SUPER then first = put(io, first, "73")
        when SCRIPT_SUB   then first = put(io, first, "74")
        end

        first = put_color(io, first, @fg, 38) unless @fg.default?
        first = put_color(io, first, @bg, 48) unless @bg.default?
        first = put_color(io, first, @ul_color, 58) unless @ul_color.default?

        io.write_byte(0x6D_u8)
      end

      private def put(io : IO, first : Bool, s : String) : Bool
        io.write_byte(0x3B_u8) unless first
        io << s
        false
      end

      private def put_color(io : IO, first : Bool, c : SgrColor, base : Int32) : Bool
        case c.kind
        in SgrColorKind::Default
          first
        in SgrColorKind::Palette
          io.write_byte(0x3B_u8) unless first
          io << base << ";5;" << c.idx
          false
        in SgrColorKind::Rgb
          io.write_byte(0x3B_u8) unless first
          io << base << ";2;" << c.r << ';' << c.g << ';' << c.b
          false
        end
      end

      private struct Param
        getter value  : Int32
        getter subs   : Array(Int32)
        getter is_sub : Bool

        def initialize(@value : Int32, @subs : Array(Int32), @is_sub : Bool)
        end
      end

      private def parse_params(bytes : Bytes, off : Int32, len : Int32) : Array(Param)
        out  = [] of Param
        i    = 0
        val  = 0
        seen = false
        subs = [] of Int32
        sub  = 0
        in_sub = false
        sub_seen = false

        flush = -> do
          subs << sub if in_sub && sub_seen
          out << Param.new(val, subs, in_sub)
          val      = 0
          seen     = false
          subs     = [] of Int32
          sub      = 0
          in_sub   = false
          sub_seen = false
        end

        while i < len
          b = bytes[off + i]
          if b >= 0x30_u8 && b <= 0x39_u8
            d = (b - 0x30_u8).to_i32
            if in_sub
              sub = sub * 10 + d
              sub_seen = true
            else
              val = val * 10 + d
              seen = true
            end
          elsif b == 0x3A_u8
            if in_sub
              subs << sub
            end
            in_sub   = true
            sub      = 0
            sub_seen = false
          elsif b == 0x3B_u8
            flush.call
          end
          i += 1
        end
        flush.call if seen || in_sub || out.empty?
        out
      end

      private def apply(params : Array(Param)) : Nil
        i = 0
        while i < params.size
          p = params[i]
          n = p.value
          case n
          when 0
            reset
          when 1  then @intensity = INTENSITY_BOLD
          when 2  then @intensity = INTENSITY_FAINT
          when 3  then @italic = true
          when 4
            @underline =
              if p.is_sub && !p.subs.empty?
                case p.subs[0]
                when 0 then UNDERLINE_NONE
                when 1 then UNDERLINE_SINGLE
                when 2 then UNDERLINE_DOUBLE
                when 3 then UNDERLINE_CURLY
                when 4 then UNDERLINE_DOTTED
                when 5 then UNDERLINE_DASHED
                else        UNDERLINE_SINGLE
                end
              else
                UNDERLINE_SINGLE
              end
          when 5  then @blink = 1_u8
          when 6  then @blink = 2_u8
          when 7  then @reverse = true
          when 8  then @conceal = true
          when 9  then @strike = true
          when 21 then @underline = UNDERLINE_DOUBLE
          when 22 then @intensity = INTENSITY_NORMAL
          when 23 then @italic = false
          when 24 then @underline = UNDERLINE_NONE
          when 25 then @blink = 0_u8
          when 27 then @reverse = false
          when 28 then @conceal = false
          when 29 then @strike = false
          when 30, 31, 32, 33, 34, 35, 36, 37
            @fg = SgrColor.palette((n - 30).to_u8)
          when 38
            c, i = read_ext_color(params, i, p)
            @fg = c
            next
          when 39 then @fg = SgrColor.default
          when 40, 41, 42, 43, 44, 45, 46, 47
            @bg = SgrColor.palette((n - 40).to_u8)
          when 48
            c, i = read_ext_color(params, i, p)
            @bg = c
            next
          when 49 then @bg = SgrColor.default
          when 53 then @overline = true
          when 55 then @overline = false
          when 58
            c, i = read_ext_color(params, i, p)
            @ul_color = c
            next
          when 59 then @ul_color = SgrColor.default
          when 73 then @script = SCRIPT_SUPER
          when 74 then @script = SCRIPT_SUB
          when 75 then @script = SCRIPT_NONE
          when 90, 91, 92, 93, 94, 95, 96, 97
            @fg = SgrColor.palette((n - 90 + 8).to_u8)
          when 100, 101, 102, 103, 104, 105, 106, 107
            @bg = SgrColor.palette((n - 100 + 8).to_u8)
          end
          i += 1
        end
      end

      private def read_ext_color(params : Array(Param), i : Int32, p : Param) : {SgrColor, Int32}
        if p.is_sub && !p.subs.empty?
          return {color_from_subs(p.subs), i}
        end

        return {SgrColor.default, i} if i + 1 >= params.size
        mode = params[i + 1].value
        case mode
        when 5
          return {SgrColor.default, i + 1} if i + 2 >= params.size
          {SgrColor.palette(clamp_u8(params[i + 2].value)), i + 2}
        when 2
          return {SgrColor.default, i + 1} if i + 4 >= params.size
          r = clamp_u8(params[i + 2].value)
          g = clamp_u8(params[i + 3].value)
          b = clamp_u8(params[i + 4].value)
          {SgrColor.rgb(r, g, b), i + 4}
        else
          {SgrColor.default, i + 1}
        end
      end

      private def color_from_subs(subs : Array(Int32)) : SgrColor
        return SgrColor.default if subs.empty?
        case subs[0]
        when 5
          return SgrColor.default if subs.size < 2
          SgrColor.palette(clamp_u8(subs[1]))
        when 2
          rest = subs.size >= 5 ? 2 : 1
          return SgrColor.default if subs.size < rest + 3
          SgrColor.rgb(clamp_u8(subs[rest]), clamp_u8(subs[rest + 1]), clamp_u8(subs[rest + 2]))
        else
          SgrColor.default
        end
      end

      private def clamp_u8(v : Int32) : UInt8
        return 0_u8 if v < 0
        return 255_u8 if v > 255
        v.to_u8
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

      sgr  = SgrState.new
      col  = 0
      io   = IO::Memory.new
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
        sgr.emit(io) if sgr.active?

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