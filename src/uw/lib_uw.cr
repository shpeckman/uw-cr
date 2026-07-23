# src/uw/lib_uw.cr

@[Link("uw", ldflags: "-L#{__DIR__}/../../ext")]
lib LibUW
  VERSION_MAJOR = 1
  VERSION_MINOR = 0
  VERSION_PATCH = 0

  enum CtrlPolicy : LibC::Int
    Skip = 0
    Fail = 1
  end

  enum Utf8Policy : LibC::Int
    Replace = 0
    Strict  = 1
  end

  struct State
    prev_gcb : UInt8
    ri_parity : UInt8
    saw_pict : UInt8
    zwj_after_pict : UInt8
    incb_consonant : UInt8
    incb_linker_seen : UInt8
    has_prev : UInt8
  end

  struct Cluster
    width : LibC::Int
    started : UInt8
    base_narrow_emoji : UInt8
    ri_count : UInt8
  end

  fun uw_unicode_version : LibC::Char*
  fun uw_active_width_cap : LibC::Int

  fun uw_width_cp(cp : UInt32) : LibC::Int

  fun uw_state_init(st : State*)
  fun uw_grapheme_break(st : State*, cp : UInt32) : LibC::Int

  fun uw_cluster_init(cl : Cluster*)
  fun uw_cluster_push(cl : Cluster*, cp : UInt32)
  fun uw_cluster_width(cl : Cluster*) : LibC::Int

  fun uw_width_utf8(s : UInt8*, n : LibC::SizeT, consumed : LibC::SizeT*,
                    policy : Utf8Policy) : LibC::Int
  fun uw_width_cps(cps : UInt32*, n : LibC::SizeT,
                   consumed : LibC::SizeT*) : LibC::Int

  fun uw_grapheme_next_utf8(s : UInt8*, n : LibC::SizeT,
                            policy : Utf8Policy) : LibC::SizeT
  fun uw_grapheme_next_cps(cps : UInt32*, n : LibC::SizeT) : LibC::SizeT

  fun uw_swidth_utf8(s : UInt8*, n : LibC::SizeT, upolicy : Utf8Policy,
                     ctrl : CtrlPolicy) : LibC::Int
  fun uw_swidth_cps(cps : UInt32*, n : LibC::SizeT,
                    ctrl : CtrlPolicy) : LibC::Int
end
