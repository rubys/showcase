# frozen_string_literal: true

# Converts Rails ERB templates to JavaScript template functions
# Handles basic Ruby constructs: if/unless/elsif, each loops, variable assignments, string interpolation
class ErbToJsConverter
  attr_reader :template, :lines, :indent_level

  def initialize(template)
    @template = template
    @lines = []
    @indent_level = 2 # Start at 2 for function body
  end

  def convert
    result = []
    result << "export function render(data) {"
    result << "  let html = '';"
    result << ""

    process_template

    result.concat(@lines)
    result << ""
    result << "  return html;"
    result << "}"

    result.join("\n")
  end

  private

  def process_template
    # Split template into tokens: plain text and ERB tags
    # Use a more robust scanning approach
    position = 0

    while position < template.length
      # Find next ERB tag
      erb_start = template.index('<%', position)

      if erb_start.nil?
        # No more ERB tags, add remaining text
        remaining = template[position..-1]
        add_html(remaining) unless remaining.empty?
        break
      end

      # Add text before ERB tag
      if erb_start > position
        text = template[position...erb_start]
        add_html(text) unless text.empty?
      end

      # Find end of ERB tag
      erb_end = template.index('%>', erb_start)
      raise "Unclosed ERB tag at position #{erb_start}" if erb_end.nil?

      # Process ERB tag
      erb_tag = template[erb_start...(erb_end + 2)]
      process_erb_tag(erb_tag)

      position = erb_end + 2
    end
  end

  def process_erb_tag(tag)
    # Remove ERB delimiters
    content = tag.gsub(/^<%=?\s*/, '').gsub(/\s*-?%>$/, '').strip

    if tag.start_with?('<%=')
      # Output expression: <%= expr %>
      add_output(ruby_to_js(content))
    else
      # Code block: <% code %>
      process_ruby_code(content)
    end
  end

  def process_ruby_code(code)
    case code
    when /^if\s+(.+)$/
      add_line("if (#{ruby_to_js($1)}) {")
      @indent_level += 1
    when /^unless\s+(.+)$/
      add_line("if (!(#{ruby_to_js($1)})) {")
      @indent_level += 1
    when /^elsif\s+(.+)$/
      @indent_level -= 1
      add_line("} else if (#{ruby_to_js($1)}) {")
      @indent_level += 1
    when /^else$/
      @indent_level -= 1
      add_line("} else {")
      @indent_level += 1
    when /^end$/
      @indent_level -= 1
      add_line("}")
    when /^(.+?)&?\.each\s+do\s+\|(.+?)\|$/
      collection = $1
      has_safe_nav = code.include?('&.')
      vars = $2.split(',').map(&:strip)
      # Convert the collection expression (handles @results[score]&.each)
      js_collection = ruby_to_js(collection)
      # Add safe navigation if it was present
      js_collection += '?' if has_safe_nav
      if vars.length > 1
        add_line("for (const [#{vars.join(', ')}] of Object.entries(#{js_collection})) {")
      else
        add_line("for (const #{vars[0]} of #{js_collection}) {")
      end
      @indent_level += 1
    when /^next\s+if\s+(.+)$/
      add_line("if (#{ruby_to_js($1)}) continue;")
    when /^(\w+)\s*=\s*(.+)$/
      var = $1
      val = $2
      add_line("const #{var} = #{ruby_to_js(val)};")
    else
      # Unknown code - add as comment for manual review
      add_line("// TODO: #{code}")
    end
  end

  def ruby_to_js(expr)
    js = expr.dup

    # Handle instance variables - convert @var to data.var
    js.gsub!(/@(\w+)/, 'data.\1')

    # Safe navigation: obj&.method -> obj?.method
    js.gsub!(/&\./, '?.')

    # Array word syntax: %w(a b c) -> ['a', 'b', 'c']
    js.gsub!(/%w\(([^)]+)\)/) { "[#{$1.split.map { |w| "'#{w}'" }.join(', ')}]" }

    # Boolean operators: 'and' -> '&&', 'or' -> '||', 'not' -> '!'
    # Do this BEFORE .blank? conversion so we can detect ! prefix
    js.gsub!(/\band\b/, '&&')
    js.gsub!(/\bor\b/, '||')
    js.gsub!(/\bnot\s+/, '!')  # 'not ' -> '!' (with space handling)

    # Method calls - order matters! Do .blank? before other checks
    # Wrap .blank? in parens when used with '!' operator
    # Match full object path (e.g., subject.entry.lead.back)
    js.gsub!(/!([\w.]+)\.blank\?/, '!(\1 == null || \1.length === 0)')
    js.gsub!(/([\w.]+)\.blank\?/, '\1 == null || \1.length === 0')
    js.gsub!(/\.empty\?/, '.length === 0')
    js.gsub!(/(\w+)\.to_s/, 'String(\1)')
    # Convert .include? to .includes() - add parens if missing
    # Match full object path (e.g., subject.category)
    js.gsub!(/\.include\?\s+([\w.]+)/, '.includes(\1)')
    js.gsub!(/\.include\?/, '.includes')
    js.gsub!(/(\w+)\.first/, '\1[0]')
    js.gsub!(/(\w+)\.last/, '\1[\1.length - 1]')

    # String methods
    js.gsub!(/\.gsub\(([^,]+),\s*([^)]+)\)/, '.replace(\1, \2)')

    # Rails helpers - handle both with and without parens
    js.gsub!(/dom_id\s+(\w+)/, 'domId(\1)')
    js.gsub!(/dom_id\(([^)]+)\)/, 'domId(\1)')
    js.gsub!(/raw\(([^)]+)\)/, '\1')  # raw() just returns unescaped

    # .html_safe - remove it (we're building strings anyway)
    js.gsub!(/\.html_safe/, '')

    # Comparison: == is same, but .nil? -> == null
    js.gsub!(/\.nil\?/, ' == null')

    js
  end

  def add_html(text)
    return if text.strip.empty?
    # Escape special characters for template literals
    # Build the JavaScript template literal string carefully to avoid Ruby interpreting backticks
    escaped = text.dup
    escaped.gsub!('\\', '\\\\\\\\')   # \ -> \\ (needs extra escaping for Ruby string interpolation)
    escaped.gsub!('`', '\\\\`')       # ` -> \` (backslash needs escaping too)
    escaped.gsub!('${', '\\\\${')     # ${ -> \${

    add_line("html += `" + escaped + "`;")
  end

  def add_output(expr)
    add_line("html += (#{expr} ?? '');")
  end

  def add_line(code)
    # Protect against negative indent from unbalanced ERB tags
    level = [@indent_level, 0].max
    @lines << ("  " * level) + code
  end
end
