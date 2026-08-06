# src/uw.cr

require "./uw/tables"
require "./uw/config"
require "./uw/props"
require "./uw/state"
require "./uw/cluster"
require "./uw/utf8"
require "./uw/iter"
require "./uw/word"
require "./uw/sentence"
require "./uw/linebreak"
require "./uw/wrap"

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

  def self.words(cps : Slice(UInt32), opts : WidthOpts = WidthOpts.unicode) : Utf32Words
    Utf32Words.new(cps, opts)
  end

  def self.words(s : Bytes, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : Utf8Words
    Utf8Words.new(s, policy, opts)
  end

  def self.words(s : String, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : Utf8Words
    Utf8Words.new(s.to_slice, policy, opts)
  end

  def self.word_next(cps : Slice(UInt32)) : Int32
    sp = Utf32Words.new(cps).next?
    sp ? sp.size : 0
  end

  def self.word_next(s : Bytes, policy : Utf8Policy = Utf8Policy::Replace) : Int32
    sp = Utf8Words.new(s, policy).next?
    sp ? sp.size : 0
  end

  def self.word_next(s : String, policy : Utf8Policy = Utf8Policy::Replace) : Int32
    word_next(s.to_slice, policy)
  end

  def self.sentences(cps : Slice(UInt32), opts : WidthOpts = WidthOpts.unicode) : Utf32Sentences
    Utf32Sentences.new(cps, opts)
  end

  def self.sentences(s : Bytes, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : Utf8Sentences
    Utf8Sentences.new(s, policy, opts)
  end

  def self.sentences(s : String, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : Utf8Sentences
    Utf8Sentences.new(s.to_slice, policy, opts)
  end

  def self.sentence_next(cps : Slice(UInt32)) : Int32
    sp = Utf32Sentences.new(cps).next?
    sp ? sp.size : 0
  end

  def self.sentence_next(s : Bytes, policy : Utf8Policy = Utf8Policy::Replace) : Int32
    sp = Utf8Sentences.new(s, policy).next?
    sp ? sp.size : 0
  end

  def self.sentence_next(s : String, policy : Utf8Policy = Utf8Policy::Replace) : Int32
    sentence_next(s.to_slice, policy)
  end

  def self.line_breaks(cps : Slice(UInt32), opts : WidthOpts = WidthOpts.unicode) : Utf32LineBreaks
    Utf32LineBreaks.new(cps, opts)
  end

  def self.line_breaks(s : Bytes, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : Utf8LineBreaks
    Utf8LineBreaks.new(s, policy, opts)
  end

  def self.line_breaks(s : String, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : Utf8LineBreaks
    Utf8LineBreaks.new(s.to_slice, policy, opts)
  end

  def self.line_break_next(cps : Slice(UInt32)) : Int32
    sp = Utf32LineBreaks.new(cps).next?
    sp ? sp.size : 0
  end

  def self.line_break_next(s : Bytes, policy : Utf8Policy = Utf8Policy::Replace) : Int32
    sp = Utf8LineBreaks.new(s, policy).next?
    sp ? sp.size : 0
  end

  def self.line_break_next(s : String, policy : Utf8Policy = Utf8Policy::Replace) : Int32
    line_break_next(s.to_slice, policy)
  end

  def self.wrap(cps : Slice(UInt32), cols : Int32, opts : WrapOpts = WrapOpts.new) : Utf32Wrap
    Utf32Wrap.new(cps, cols, opts)
  end

  def self.wrap(s : Bytes, cols : Int32, policy : Utf8Policy = Utf8Policy::Replace, opts : WrapOpts = WrapOpts.new) : Utf8Wrap
    Utf8Wrap.new(s, cols, policy, opts)
  end

  def self.wrap(s : String, cols : Int32, policy : Utf8Policy = Utf8Policy::Replace, opts : WrapOpts = WrapOpts.new) : Utf8Wrap
    Utf8Wrap.new(s.to_slice, cols, policy, opts)
  end

  def self.clusters(cps : Slice(UInt32), opts : WidthOpts = WidthOpts.unicode) : Utf32Clusters
    Utf32Clusters.new(cps, opts)
  end

  def self.clusters(s : Bytes, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : Utf8Clusters
    Utf8Clusters.new(s, policy, opts)
  end

  def self.clusters(s : String, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : Utf8Clusters
    Utf8Clusters.new(s.to_slice, policy, opts)
  end

  def self.width_cp(cp : UInt32, mode : WidthMode = WidthMode::Unicode) : Int32
    p = Props.props(cp)
    w = mode.legacy? ? Props.legacy_width(p) : Props.width(p)
    w == 3 ? -1 : w
  end

  def self.width_cp(cp : UInt32, opts : WidthOpts) : Int32
    p = Props.props(cp)
    w = opts.mode.legacy? ? Props.legacy_width(p) : Props.width(p)
    return -1 if w == 3
    w = 2 if opts.ambiguous_wide && w == 1 && Props.ambiguous?(p)
    w
  end

  def self.width(cps : Slice(UInt32), opts : WidthOpts = WidthOpts.unicode) : {Int32, Int32}
    n = cps.size
    if n == 0
      return {0, 0}
    end
    st  = State.new
    cl  = Cluster.new(opts.cap, opts.mode, opts.ambiguous_wide)
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

  def self.width(s : Bytes, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : {Int32, Int32}
    n = s.size
    if n == 0
      return {0, 0}
    end
    st  = State.new
    cl  = Cluster.new(opts.cap, opts.mode, opts.ambiguous_wide)
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

  def self.width(s : String, policy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : {Int32, Int32}
    width(s.to_slice, policy, opts)
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

  def self.swidth(cps : Slice(UInt32), ctrl : CtrlPolicy = CtrlPolicy::Skip, opts : WidthOpts = WidthOpts.unicode) : Int32
    st           = State.new
    cl           = Cluster.new(opts.cap, opts.mode, opts.ambiguous_wide)
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

  def self.swidth(s : Bytes, upolicy : Utf8Policy = Utf8Policy::Replace, ctrl : CtrlPolicy = CtrlPolicy::Skip, opts : WidthOpts = WidthOpts.unicode) : Int32
    st           = State.new
    cl           = Cluster.new(opts.cap, opts.mode, opts.ambiguous_wide)
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

  def self.swidth(s : String, upolicy : Utf8Policy = Utf8Policy::Replace, ctrl : CtrlPolicy = CtrlPolicy::Skip, opts : WidthOpts = WidthOpts.unicode) : Int32
    swidth(s.to_slice, upolicy, ctrl, opts)
  end

  def self.truncate(cps : Slice(UInt32), max_cols : Int32, opts : WidthOpts = WidthOpts.unicode) : {Int32, Int32}
    return {0, 0} if max_cols <= 0
    st  = State.new
    cl  = Cluster.new(opts.cap, opts.mode, opts.ambiguous_wide)
    ptr = cps.to_unsafe
    n   = cps.size

    total         = 0
    cluster_start = 0
    have_cluster  = false
    i             = 0
    while i < n
      cp = ptr[i]
      p  = Props.props(cp)
      if st.grapheme_break(cp, p) && have_cluster
        w  = cl.display_width
        cw = w < 0 ? 0 : w
        if total + cw > max_cols
          return {total, cluster_start}
        end
        total += cw
        cl.reset
        cluster_start = i
      end
      cl.push(cp, p)
      have_cluster = true
      i += 1
    end
    if have_cluster
      w  = cl.display_width
      cw = w < 0 ? 0 : w
      if total + cw > max_cols
        return {total, cluster_start}
      end
      total += cw
    end
    {total, n}
  end

  def self.truncate(s : Bytes, max_cols : Int32, upolicy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : {Int32, Int32}
    return {0, 0} if max_cols <= 0
    st  = State.new
    cl  = Cluster.new(opts.cap, opts.mode, opts.ambiguous_wide)
    ptr = s.to_unsafe
    n   = s.size

    total         = 0
    cluster_start = 0
    have_cluster  = false
    i             = 0
    while i < n
      cp, len, bad = utf8_decode(ptr + i, n - i)
      break if bad && upolicy.strict?
      p = Props.props(cp)
      if st.grapheme_break(cp, p) && have_cluster
        w  = cl.display_width
        cw = w < 0 ? 0 : w
        if total + cw > max_cols
          return {total, cluster_start}
        end
        total += cw
        cl.reset
        cluster_start = i
      end
      cl.push(cp, p)
      have_cluster = true
      i += len
    end
    if have_cluster
      w  = cl.display_width
      cw = w < 0 ? 0 : w
      if total + cw > max_cols
        return {total, cluster_start}
      end
      total += cw
    end
    {total, n}
  end

  def self.truncate(s : String, max_cols : Int32, upolicy : Utf8Policy = Utf8Policy::Replace, opts : WidthOpts = WidthOpts.unicode) : {Int32, Int32}
    truncate(s.to_slice, max_cols, upolicy, opts)
  end
end
