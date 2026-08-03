# src/uw/utf8.cr

module UW
  @[AlwaysInline]
  protected def self.utf8_decode(s : Pointer(UInt8), n : Int32) : {UInt32, Int32, Bool}
    c = s[0]
    return {c.to_u32, 1, false} if c < 0x80

    if (c & 0xE0) == 0xC0
      len = 2
      min = 0x80_u32
      acc = (c & 0x1F).to_u32
    elsif (c & 0xF0) == 0xE0
      len = 3
      min = 0x800_u32
      acc = (c & 0x0F).to_u32
    elsif (c & 0xF8) == 0xF0
      len = 4
      min = 0x10000_u32
      acc = (c & 0x07).to_u32
    else
      return {0xFFFD_u32, 1, true}
    end

    return {0xFFFD_u32, 1, true} if len > n

    i = 1
    while i < len
      ci = s[i]
      return {0xFFFD_u32, 1, true} if (ci & 0xC0) != 0x80
      acc = (acc << 6) | (ci & 0x3F).to_u32
      i += 1
    end

    if acc < min || acc > 0x10FFFF_u32 || (acc >= 0xD800_u32 && acc <= 0xDFFF_u32)
      return {0xFFFD_u32, 1, true}
    end
    {acc, len, false}
  end
end
