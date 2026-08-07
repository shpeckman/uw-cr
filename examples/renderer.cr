# renderer.cr

require "../src/uw-cr"

record Rect, x : Int32, y : Int32, width : Int32, height : Int32 do
  def intersects?(other : Rect) : Bool
    x < (other.x + other.width) &&
      (x + width) > other.x &&
      y < (other.y + other.height) &&
      (y + height) > other.y
  end

  def merge(other : Rect) : Rect
    min_x = x < other.x ? x : other.x
    min_y = y < other.y ? y : other.y
    max_x = (x + width) > (other.x + other.width) ? (x + width) : (other.x + other.width)
    max_y = (y + height) > (other.y + other.height) ? (y + height) : (other.y + other.height)
    Rect.new(min_x, min_y, max_x - min_x, max_y - min_y)
  end

  def intersection(other : Rect) : Rect?
    return nil unless intersects?(other)
    min_x = x > other.x ? x : other.x
    min_y = y > other.y ? y : other.y
    max_x = (x + width) < (other.x + other.width) ? (x + width) : (other.x + other.width)
    max_y = (y + height) < (other.y + other.height) ? (y + height) : (other.y + other.height)
    Rect.new(min_x, min_y, max_x - min_x, max_y - min_y)
  end
end

record RenderNode,
  id : UInt64,
  rect : Rect,
  z_index : Int32,
  state_hash : UInt64,
  text : String,
  fg : UInt8,
  bg : UInt8

record MoveCursorCommand, x : Int32, y : Int32
record PrintTextCommand, text : String
record SetStyleCommand, fg : UInt8, bg : UInt8

alias DrawCommand = MoveCursorCommand | PrintTextCommand | SetStyleCommand

class DamageTracker
  property previous_nodes : Array(RenderNode)
  property current_nodes : Array(RenderNode)
  property damage_rects : Array(Rect)
  property prev_map : Hash(UInt64, RenderNode)

  def initialize
    @previous_nodes = Array(RenderNode).new
    @current_nodes = Array(RenderNode).new
    @damage_rects = Array(Rect).new
    @prev_map = Hash(UInt64, RenderNode).new(initial_capacity: 1024)
  end

  def compute_damage
    @damage_rects.clear
    @prev_map.clear

    @previous_nodes.each do |node|
      @prev_map[node.id] = node
    end

    @current_nodes.each do |node|
      prev_node = @prev_map[node.id]?

      if prev_node
        if prev_node.rect != node.rect
          @damage_rects << prev_node.rect
          @damage_rects << node.rect
        elsif prev_node.state_hash != node.state_hash
          @damage_rects << node.rect
        elsif prev_node.z_index != node.z_index
          @damage_rects << node.rect
        end
        @prev_map.delete(node.id)
      else
        @damage_rects << node.rect
      end
    end

    @prev_map.each_value do |deleted_node|
      @damage_rects << deleted_node.rect
    end

    consolidate_damage
  end

  private def consolidate_damage
    loop do
      merged_any = false
      i = 0
      while i < @damage_rects.size
        j = i + 1
        while j < @damage_rects.size
          if @damage_rects[i].intersects?(@damage_rects[j])
            @damage_rects[i] = @damage_rects[i].merge(@damage_rects[j])
            @damage_rects.delete_at(j)
            merged_any = true
          else
            j += 1
          end
        end
        i += 1
      end
      break unless merged_any
    end
  end
end

class Pipeline
  property current_nodes : Array(RenderNode)
  property previous_nodes : Array(RenderNode)
  property tracker : DamageTracker
  property commands : Array(DrawCommand)

  def initialize
    @current_nodes = Array(RenderNode).new(initial_capacity: 1024)
    @previous_nodes = Array(RenderNode).new(initial_capacity: 1024)
    @tracker = DamageTracker.new
    @commands = Array(DrawCommand).new(initial_capacity: 8192)
  end

  def begin_frame
    temp = @previous_nodes
    @previous_nodes = @current_nodes
    @current_nodes = temp
    @current_nodes.clear
  end

  def push_node(node : RenderNode)
    @current_nodes << node
  end

  def end_frame
    @current_nodes.sort_by!(&.z_index)
    @tracker.previous_nodes = @previous_nodes
    @tracker.current_nodes = @current_nodes
    @tracker.compute_damage
  end

  def render(io : IO)
    @commands.clear
    @tracker.damage_rects.each do |clip_area|
      @current_nodes.each do |node|
        emit_commands(node, clip_area)
      end
    end

    @commands.each do |cmd|
      case cmd
      when MoveCursorCommand
        io << "\e[" << (cmd.y + 1) << ';' << (cmd.x + 1) << 'H'
      when PrintTextCommand
        io << cmd.text
      when SetStyleCommand
        io << "\e[38;5;" << cmd.fg << "m\e[48;5;" << cmd.bg << 'm'
      end
    end
    io << "\e[0m"
    io.flush
  end

  private def field(line : String, start_col : Int32, cols : Int32) : String
    return "" if cols <= 0
    slice = UW.slice_cols(line, start_col, start_col + cols)
    body = line.byte_slice(slice.offset, slice.size)
    body_width = UW.swidth(body)
    used = slice.pad_left + body_width + slice.pad_right
    tail = cols - used
    tail = 0 if tail < 0
    String.build(body.bytesize + slice.pad_left + slice.pad_right + tail) do |sb|
      slice.pad_left.times { sb << ' ' }
      sb << body
      slice.pad_right.times { sb << ' ' }
      tail.times { sb << ' ' }
    end
  end

  private def emit_commands(node : RenderNode, clip_area : Rect)
    local_clip = node.rect.intersection(clip_area)
    return unless local_clip

    start_x = local_clip.x - node.rect.x
    start_y = local_clip.y - node.rect.y

    @commands << SetStyleCommand.new(node.fg, node.bg)

    current_y = 0
    node.text.each_line do |line|
      if current_y >= start_y && current_y < start_y + local_clip.height
        screen_x = local_clip.x
        screen_y = local_clip.y + (current_y - start_y)

        text = field(line, start_x, local_clip.width)
        @commands << MoveCursorCommand.new(screen_x, screen_y)
        @commands << PrintTextCommand.new(text) unless text.empty?
      end
      current_y += 1
    end

    while current_y < start_y + local_clip.height
      screen_x = local_clip.x
      screen_y = local_clip.y + (current_y - start_y)
      @commands << MoveCursorCommand.new(screen_x, screen_y)
      @commands << PrintTextCommand.new(field("", 0, local_clip.width))
      current_y += 1
    end
  end
end

term_height = 64
term_width = 95

begin
  size_parts = `stty size`.strip.split
  if size_parts.size == 2
    term_height = size_parts[0].to_i
    term_width = size_parts[1].to_i
  end
rescue
end

pipeline = Pipeline.new
STDOUT << "\e[?1049h\e[?25l"
STDOUT << "\e[2J"
STDOUT.flush

box1_w = 30
box1_h = 8
box1_x = 5
box1_y = 5
box1_dx = 2
box1_dy = 1

box2_w = 26
box2_h = 6
box2_x = term_width - 35
box2_y = term_height - 15
box2_dx = -3
box2_dy = -2

bg_line = ("+ " * (term_width // 2 + 1))[0, term_width]
bg_text = (0...term_height).map { |i| (i % 2 == 0) ? bg_line : bg_line.reverse }.join("\n")

begin
  300.times do |i|
    pipeline.begin_frame

    pipeline.push_node(RenderNode.new(
      id: 1_u64,
      rect: Rect.new(0, 0, term_width, term_height),
      z_index: 0,
      state_hash: 1_u64,
      text: bg_text,
      fg: 240_u8,
      bg: 235_u8
    ))

    box1_x += box1_dx
    box1_y += box1_dy

    if box1_x <= 0
      box1_x = 0
      box1_dx = -box1_dx
    elsif box1_x + box1_w >= term_width
      box1_x = term_width - box1_w
      box1_dx = -box1_dx
    end

    if box1_y <= 0
      box1_y = 0
      box1_dy = -box1_dy
    elsif box1_y + box1_h >= term_height
      box1_y = term_height - box1_h
      box1_dy = -box1_dy
    end

    box1_text = "BOUNCING WINDOW 1\n\n\u65E5\u672C\u8A9E W:#{box1_w} H:#{box1_h}\nPos X: #{box1_x} Pos Y: #{box1_y}\nFrame: #{i} \u{1F600}"
    pipeline.push_node(RenderNode.new(
      id: 2_u64,
      rect: Rect.new(box1_x, box1_y, box1_w, box1_h),
      z_index: 1,
      state_hash: box1_text.hash,
      text: box1_text,
      fg: 15_u8,
      bg: 27_u8
    ))

    box2_x += box2_dx
    box2_y += box2_dy

    if box2_x <= 0
      box2_x = 0
      box2_dx = -box2_dx
    elsif box2_x + box2_w >= term_width
      box2_x = term_width - box2_w
      box2_dx = -box2_dx
    end

    if box2_y <= 0
      box2_y = 0
      box2_dy = -box2_dy
    elsif box2_y + box2_h >= term_height
      box2_y = term_height - box2_h
      box2_dy = -box2_dy
    end

    box2_text = "BOUNCING WINDOW 2\n\n\u{1F1EF}\u{1F1F5} Collision\nPos X: #{box2_x} Pos Y: #{box2_y}"
    pipeline.push_node(RenderNode.new(
      id: 3_u64,
      rect: Rect.new(box2_x, box2_y, box2_w, box2_h),
      z_index: 2,
      state_hash: box2_text.hash,
      text: box2_text,
      fg: 0_u8,
      bg: 214_u8
    ))

    pipeline.end_frame
    pipeline.render(STDOUT)

    sleep 0.03
  end
ensure
  STDOUT << "\e[?1049l\e[?25h"
  STDOUT.flush
end