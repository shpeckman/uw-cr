# src/uw.cr

require "./uw/tables"
require "./uw/props"
require "./uw/state"
require "./uw/cluster"
require "./uw/utf8"

module UW
  {% unless @type.has_constant?("CLUSTER_WIDTH_CAP") %}
    CLUSTER_WIDTH_CAP = 2
  {% end %}

  enum CtrlPolicy
    Skip = 0
    Fail = 1
  end

  enum Utf8Policy
    Replace = 0
    Strict  = 1
  end

  def self.unicode_version : String
    UNICODE_VERSION
  end

  def self.width_cp(cp : UInt32) : Int32
    w = Props.width(Props.props(cp))
    w == 3 ? -1 : w
  end

  def self.width(cps : Slice(UInt32)) : {Int32, Int32}
    n = cps.size
    if n == 0
      return {0, 0}
    end
    st  = State.new
    cl  = Cluster.new
    ptr = cps.to_unsafe
    i   = 0
    while i < n
      cp = ptr[i]
      p  = Props.props(cp)
      break if st.grapheme_break(cp, p) && cl.started
      cl.push(cp, p)
      i += 1
    end
    {cl.display_width, i}
  end

  def self.width(s : Bytes, policy : Utf8Policy = Utf8Policy::Replace) : {Int32, Int32}
    n = s.size
    if n == 0
      return {0, 0}
    end
    st  = State.new
    cl  = Cluster.new
    ptr = s.to_unsafe
    i   = 0
    while i < n
      cp, len, bad = utf8_decode(ptr + i, n - i)
      break if bad && policy.strict?
      p = Props.props(cp)
      break if st.grapheme_break(cp, p) && cl.started
      cl.push(cp, p)
      i += len
    end
    {cl.display_width, i}
  end

  def self.width(s : String, policy : Utf8Policy = Utf8Policy::Replace) : {Int32, Int32}
    width(s.to_slice, policy)
  end

  def self.grapheme_next(cps : Slice(UInt32)) : Int32
    _, consumed = width(cps)
    consumed
  end

  def self.grapheme_next(s : Bytes, policy : Utf8Policy = Utf8Policy::Replace) : Int32
    _, consumed = width(s, policy)
    consumed
  end

  def self.grapheme_next(s : String, policy : Utf8Policy = Utf8Policy::Replace) : Int32
    grapheme_next(s.to_slice, policy)
  end

  def self.swidth(cps : Slice(UInt32), ctrl : CtrlPolicy = CtrlPolicy::Skip) : Int32
    st           = State.new
    cl           = Cluster.new
    total        = 0
    have_cluster = false
    ptr          = cps.to_unsafe
    n            = cps.size

    i = 0
    while i < n
      cp = ptr[i]
      p  = Props.props(cp)
      if st.grapheme_break(cp, p) && have_cluster
        w = cl.display_width
        if w < 0
          return -1 if ctrl.fail?
        else
          total += w
        end
        cl.reset
      end
      cl.push(cp, p)
      have_cluster = true
      i += 1
    end
    if have_cluster
      w = cl.display_width
      if w < 0
        return -1 if ctrl.fail?
      else
        total += w
      end
    end
    total
  end

  def self.swidth(s : Bytes, upolicy : Utf8Policy = Utf8Policy::Replace, ctrl : CtrlPolicy = CtrlPolicy::Skip) : Int32
    st           = State.new
    cl           = Cluster.new
    total        = 0
    have_cluster = false
    ptr          = s.to_unsafe
    n            = s.size

    i = 0
    while i < n
      cp, len, bad = utf8_decode(ptr + i, n - i)
      break if bad && upolicy.strict?
      p = Props.props(cp)
      if st.grapheme_break(cp, p) && have_cluster
        w = cl.display_width
        if w < 0
          return -1 if ctrl.fail?
        else
          total += w
        end
        cl.reset
      end
      cl.push(cp, p)
      have_cluster = true
      i += len
    end
    if have_cluster
      w = cl.display_width
      if w < 0
        return -1 if ctrl.fail?
      else
        total += w
      end
    end
    total
  end

  def self.swidth(s : String, upolicy : Utf8Policy = Utf8Policy::Replace, ctrl : CtrlPolicy = CtrlPolicy::Skip) : Int32
    swidth(s.to_slice, upolicy, ctrl)
  end
end
