# src/uw/cluster.cr

module UW
  struct Cluster
    getter started : Bool

    def initialize
      @width = 0
      @started = false
      @base_narrow_emoji = false
      @ri_count = 0_u8
    end

    def reset : Nil
      @width = 0
      @started = false
      @base_narrow_emoji = false
      @ri_count = 0_u8
    end

    def push(cp : UInt32) : Nil
      p = UW::Props.props(cp)
      gcb = UW::Props.gcb(p)
      w = UW::Props.width(p)

      if gcb == GCB_RI
        @ri_count += 1
        if !@started
          @width = 1
          @started = true
        end
        @width = 2 if @ri_count == 2
        return
      end

      if cp == VS16
        @width = 2 if @base_narrow_emoji
        return
      end
      if cp == VS15
        @width = 1 if @base_narrow_emoji
        return
      end

      if !@started
        @started = true
        @width = (w == 3) ? -1 : w
        @base_narrow_emoji = true if !UW::Props.epres?(p) && w != 2
      end
    end

    def display_width : Int32
      return -1 if @width < 0
      {% if CLUSTER_WIDTH_CAP > 0 %}
        @width > CLUSTER_WIDTH_CAP ? CLUSTER_WIDTH_CAP : @width
      {% else %}
        @width
      {% end %}
    end
  end
end