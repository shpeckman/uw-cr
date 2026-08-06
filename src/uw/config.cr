# src/uw/config.cr

module UW
  enum WidthMode
    Unicode = 0
    Legacy  = 1
  end

  enum Mode2027State
    NotRecognized    = 0
    Set              = 1
    Reset            = 2
    PermanentlySet   = 3
    PermanentlyReset = 4
  end

  struct WidthOpts
    getter mode           : WidthMode
    getter cap            : Int32
    getter ambiguous_wide : Bool

    def initialize(@mode : WidthMode = WidthMode::Unicode, @cap : Int32 = CLUSTER_WIDTH_CAP, @ambiguous_wide : Bool = false)
    end

    def self.unicode : WidthOpts
      new(WidthMode::Unicode, CLUSTER_WIDTH_CAP, false)
    end

    def self.legacy : WidthOpts
      new(WidthMode::Legacy, CLUSTER_WIDTH_CAP, false)
    end

    def with_mode(mode : WidthMode) : WidthOpts
      WidthOpts.new(mode, @cap, @ambiguous_wide)
    end

    def with_cap(cap : Int32) : WidthOpts
      WidthOpts.new(@mode, cap, @ambiguous_wide)
    end

    def with_ambiguous_wide(ambiguous_wide : Bool) : WidthOpts
      WidthOpts.new(@mode, @cap, ambiguous_wide)
    end
  end

  struct Config
    property supported : Bool
    property state     : Mode2027State

    def initialize(@supported : Bool = false, @state : Mode2027State = Mode2027State::NotRecognized)
    end

    def grapheme_processing? : Bool
      @supported && (@state.set? || @state.permanently_set?)
    end

    def width_mode : WidthMode
      grapheme_processing? ? WidthMode::Unicode : WidthMode::Legacy
    end

    def opts(cap : Int32 = CLUSTER_WIDTH_CAP) : WidthOpts
      WidthOpts.new(width_mode, cap)
    end
  end
end