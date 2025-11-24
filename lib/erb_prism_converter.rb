# frozen_string_literal: true

require 'erb'
require 'prism'

# Converts Rails ERB templates to JavaScript using ERB compilation + Prism AST
class ErbPrismConverter
  attr_reader :template, :lines, :indent_level

  def initialize(template)
    @template = template
    @lines = []
    @indent_level = 2 # Start at 2 for function body
    @local_vars = Set.new # Track local variables from loops/assignments
  end

  def convert
    # Step 1: Compile ERB to Ruby using Rails' ERB handler
    ruby_code = compile_with_rails_handler(@template)

    # Step 2: Parse with Prism
    result = Prism.parse(ruby_code)

    unless result.success?
      raise "Prism failed to parse compiled ERB: #{result.errors.map(&:message).join(', ')}"
    end

    # Step 3: Scan for all local variables (for hoisting)
    scan_for_local_vars(result.value.statements.body)

    # Step 4: Generate JavaScript
    result_lines = []
    result_lines << "export function render(data) {"
    result_lines << "  let html = '';"

    # Hoist local variable declarations to avoid block-scoping issues
    unless @local_vars.empty?
      hoisted_vars = @local_vars.to_a.sort.join(', ')
      result_lines << "  let #{hoisted_vars};"
    end

    result_lines << ""

    # Process each top-level statement
    result.value.statements.body.each do |stmt|
      process_statement(stmt)
    end

    result_lines.concat(@lines)
    result_lines << ""
    result_lines << "  return html;"
    result_lines << "}"

    result_lines.join("\n")
  end

  private

  # Scan AST to find all local variable assignments (for hoisting)
  def scan_for_local_vars(statements)
    statements.each do |stmt|
      scan_statement_for_vars(stmt)
    end
  end

  def scan_statement_for_vars(stmt)
    case stmt
    when Prism::LocalVariableWriteNode
      # Track this variable (skip _erbout)
      @local_vars.add(stmt.name) unless stmt.name == :_erbout

    when Prism::IfNode
      # Scan if body
      stmt.statements&.body&.each { |s| scan_statement_for_vars(s) }
      # Scan elsif/else
      scan_consequent_for_vars(stmt.subsequent) if stmt.subsequent

    when Prism::UnlessNode
      stmt.statements&.body&.each { |s| scan_statement_for_vars(s) }
      stmt.else_clause&.statements&.body&.each { |s| scan_statement_for_vars(s) }

    when Prism::CallNode
      # Scan each/each_with_index loops for assignments in their bodies
      if (stmt.name == :each || stmt.name == :each_with_index) && stmt.block
        # Track loop parameters as local variables
        block_params = stmt.block.parameters
        if block_params && block_params.parameters
          param_nodes = block_params.parameters.requireds || []
          param_nodes.each { |param| @local_vars.add(param.name) }
        end
        # Scan loop body for assignments
        stmt.block.body&.body&.each { |s| scan_statement_for_vars(s) }
      end
    end
  end

  def scan_consequent_for_vars(consequent)
    case consequent
    when Prism::ElseNode
      consequent.statements&.body&.each { |s| scan_statement_for_vars(s) }
    when Prism::IfNode
      consequent.statements&.body&.each { |s| scan_statement_for_vars(s) }
      scan_consequent_for_vars(consequent.subsequent) if consequent.subsequent
    end
  end

  def process_statement(stmt)
    case stmt
    when Prism::LocalVariableWriteNode
      # _erbout = +'' → skip
      return if stmt.name == :_erbout

      # Regular variable assignment
      # Variable is already hoisted, so just do assignment (not declaration)
      js_value = ruby_to_js(stmt.value)
      add_line("#{stmt.name} = #{js_value};")

    when Prism::CallNode
      process_call_statement(stmt)

    when Prism::IfNode
      process_if_node(stmt)

    when Prism::UnlessNode
      process_unless_node(stmt)

    when Prism::LocalVariableReadNode
      # Final _erbout → skip
      return if stmt.name == :_erbout

    when Prism::InstanceVariableReadNode
      # Final @output_buffer → skip (Rails ERB format)
      return if stmt.name == :@output_buffer

    when Prism::NextNode
      # Ruby 'next' in a loop → JavaScript 'continue'
      add_line("continue;")

    else
      add_line("// TODO: #{stmt.class.name}")
    end
  end

  def process_call_statement(node)
    # Check if this is _erbout.<< ... (output statement) - old ERB format
    if node.name == :<<
      if node.receiver.is_a?(Prism::LocalVariableReadNode) && node.receiver.name == :_erbout
        process_output(node.arguments.arguments[0])
        return
      end
    end

    # Check if this is @output_buffer.safe_append= or @output_buffer.append= - Rails ERB format
    if node.name == :safe_append= || node.name == :append=
      if node.receiver.is_a?(Prism::InstanceVariableReadNode) && node.receiver.name == :@output_buffer
        process_output(node.arguments.arguments[0])
        return
      end
    end

    # Check if this is a .each or .each_with_index loop at statement level
    if (node.name == :each || node.name == :each_with_index) && node.block
      process_each_loop(node)
      return
    end

    # Check if this is link_to with a block - stub it out for SPA
    if node.name == :link_to && node.block
      # Just render the block contents without the link wrapper
      # The SPA will handle navigation differently
      node.block.body&.body&.each { |stmt| process_statement(stmt) }
      return
    end

    # Check for next statement
    if node.name == :next
      # Pattern: next if condition
      if node.arguments && node.arguments.arguments.length > 0
        # This shouldn't happen at statement level, but handle it
        add_line("continue;")
      else
        add_line("continue;")
      end
      return
    end

    # Check for mutating methods that need to be converted to assignments
    if node.name.to_s.end_with?('!') && node.receiver
      # Mutating methods like map!, select!, etc. need reassignment in JavaScript
      receiver_js = ruby_to_js(node.receiver)
      # Convert the call but strip the ! from the method name
      method_without_bang = node.name.to_s.chomp('!')
      modified_node = node.dup
      modified_node.instance_variable_set(:@name, method_without_bang.to_sym)
      call_js = ruby_to_js(modified_node)
      add_line("#{receiver_js} = #{call_js};")
      return
    end

    # Other statement-level calls (assignments, etc.)
    js_expr = ruby_to_js(node)
    add_line("#{js_expr};")
  end

  def process_output(arg)
    case arg
    when Prism::StringNode
      # Static HTML: _erbout.<< "text".freeze
      add_html(arg.unescaped)

    when Prism::CallNode
      # Could be dynamic output or string interpolation
      if arg.name == :link_to && arg.block
        # link_to with block -> just render the block contents, skip the link wrapper
        arg.block.body&.body&.each { |stmt| process_statement(stmt) }
      elsif arg.name == :to_s && arg.receiver.is_a?(Prism::ParenthesesNode)
        # Pattern: _erbout.<<(( expr ).to_s)
        inner_expr = arg.receiver.body.body[0]
        js_expr = ruby_to_js(inner_expr)
        add_output(js_expr)
      elsif arg.name == :freeze && arg.receiver.is_a?(Prism::StringNode)
        # Pattern: "text".freeze
        add_html(arg.receiver.unescaped)
      elsif arg.name == :freeze && arg.receiver.is_a?(Prism::InterpolatedStringNode)
        # Pattern: "text #{expr}".freeze
        add_interpolated_string(arg.receiver)
      else
        # Other call - convert to JS
        js_expr = ruby_to_js(arg)
        add_output(js_expr)
      end

    when Prism::InterpolatedStringNode
      # String interpolation without .freeze
      add_interpolated_string(arg)

    else
      js_expr = ruby_to_js(arg)
      add_output(js_expr)
    end
  end

  def process_if_node(node)
    condition = ruby_to_js(node.predicate)
    add_line("if (#{condition}) {")
    @indent_level += 1

    # Process if body
    node.statements&.body&.each { |stmt| process_statement(stmt) }

    # Handle elsif/else chain - use subsequent instead of consequent
    process_consequent(node.subsequent)

    @indent_level -= 1
    add_line("}")
  end

  def process_consequent(consequent)
    return unless consequent

    case consequent
    when Prism::ElseNode
      @indent_level -= 1
      add_line("} else {")
      @indent_level += 1
      consequent.statements&.body&.each { |stmt| process_statement(stmt) }

    when Prism::IfNode
      # This is elsif
      @indent_level -= 1
      condition = ruby_to_js(consequent.predicate)
      add_line("} else if (#{condition}) {")
      @indent_level += 1
      consequent.statements&.body&.each { |stmt| process_statement(stmt) }
      # Recursively handle more elsifs - use subsequent instead of consequent
      process_consequent(consequent.subsequent)
    end
  end

  def process_unless_node(node)
    condition = ruby_to_js(node.predicate)
    add_line("if (!(#{condition})) {")
    @indent_level += 1

    node.statements&.body&.each { |stmt| process_statement(stmt) }

    if node.else_clause
      @indent_level -= 1
      add_line("} else {")
      @indent_level += 1
      node.else_clause.statements&.body&.each { |stmt| process_statement(stmt) }
    end

    @indent_level -= 1
    add_line("}")
  end

  def process_each_loop(node)
    # Get the collection
    collection = ruby_to_js(node.receiver)

    # Get block parameters
    block = node.block
    block_params = block.parameters

    if block_params && block_params.parameters
      # BlockParametersNode has a parameters property (ParametersNode)
      # ParametersNode has requireds (array of RequiredParameterNode)
      param_nodes = block_params.parameters.requireds || []

      # Extract parameter names
      param_names = param_nodes.map { |param| param.name.to_s }

      # Track these as local variables
      param_names.each { |name| @local_vars.add(name.to_sym) }

      # Check for safe navigation on the collection call
      flags = node.instance_variable_get(:@flags)
      is_safe_nav = (flags & Prism::CallNodeFlags::SAFE_NAVIGATION) != 0

      # Wrap in || [] for safe navigation
      collection = "(#{collection} || [])" if is_safe_nav

      if param_names.length == 1
        # Simple each: items.each do |item|
        # Don't use 'const' since variable is hoisted
        add_line("for (#{param_names[0]} of #{collection}) {")
      elsif node.name == :each_with_index
        # each_with_index: items.each_with_index do |item, index|
        # Use .entries() to get [index, value] pairs
        temp_var = "_temp_#{param_names.join('_')}"
        add_line("for (const #{temp_var} of #{collection}.entries()) {")
        @indent_level += 1
        # entries() returns [index, value], so assign appropriately
        add_line("#{param_names[1]} = #{temp_var}[0];") # index
        add_line("#{param_names[0]} = #{temp_var}[1];") # value
        @indent_level -= 1
      else
        # each with multiple params (hash iteration, etc.)
        # Use temporary for destructuring, then assign to hoisted variables
        temp_var = "_temp_#{param_names.join('_')}"
        add_line("for (const #{temp_var} of Object.entries(#{collection})) {")
        @indent_level += 1
        param_names.each_with_index do |name, idx|
          add_line("#{name} = #{temp_var}[#{idx}];")
        end
        @indent_level -= 1
      end
    else
      # No parameters - shouldn't happen, but handle it
      add_line("for (const item of #{collection}) {")
      @local_vars.add(:item)
    end

    @indent_level += 1

    # Process block body
    block.body&.body&.each { |stmt| process_statement(stmt) }

    @indent_level -= 1
    add_line("}")
  end

  def add_interpolated_string(node)
    # Convert "text #{expr}" to template literal
    parts = node.parts.map do |part|
      case part
      when Prism::StringNode
        part.unescaped
      when Prism::EmbeddedStatementsNode
        # Extract the expression and convert to JS
        expr = part.statements.body[0]
        "${#{ruby_to_js(expr)}}"
      else
        "${/* TODO: #{part.class.name} */}"
      end
    end

    text = parts.join
    add_line("html += `#{text}`;")
  end

  def ruby_to_js(node)
    case node
    when Prism::InstanceVariableReadNode
      "data.#{node.name.to_s.delete_prefix('@')}"

    when Prism::CallNode
      convert_call(node)

    when Prism::LocalVariableReadNode
      # Check for JavaScript global objects
      if node.name == :console
        "console"
      # Check if it's a known local variable
      elsif @local_vars.include?(node.name)
        node.name.to_s
      else
        # Assume it's from template data
        "data.#{node.name}"
      end

    when Prism::ItLocalVariableReadNode
      # Ruby 3.4+ numbered parameter: `it` is the implicit block parameter
      "it"

    when Prism::StringNode
      "\"#{escape_js_string(node.unescaped)}\""

    when Prism::InterpolatedStringNode
      # Convert to template literal
      parts = node.parts.map do |part|
        case part
        when Prism::StringNode
          part.unescaped
        when Prism::EmbeddedStatementsNode
          expr = part.statements.body[0]
          "${#{ruby_to_js(expr)}}"
        else
          "${/* TODO */}"
        end
      end
      "`#{parts.join}`"

    when Prism::SymbolNode
      "'#{node.unescaped}'"

    when Prism::IntegerNode
      node.value.to_s

    when Prism::TrueNode
      "true"

    when Prism::FalseNode
      "false"

    when Prism::NilNode
      "null"

    when Prism::AndNode
      "(#{ruby_to_js(node.left)}) && (#{ruby_to_js(node.right)})"

    when Prism::OrNode
      "(#{ruby_to_js(node.left)}) || (#{ruby_to_js(node.right)})"

    when Prism::CallAndWriteNode
      # a &&= b
      "#{node.name} = #{node.name} && #{ruby_to_js(node.value)}"

    when Prism::CallOrWriteNode
      # a ||= b
      "#{node.name} = #{node.name} || #{ruby_to_js(node.value)}"

    when Prism::ArrayNode
      elements = node.elements.map { |el| ruby_to_js(el) }
      "[#{elements.join(', ')}]"

    when Prism::HashNode
      if node.elements.empty?
        "{}"
      else
        pairs = node.elements.map do |assoc|
          key = ruby_to_js(assoc.key)
          value = ruby_to_js(assoc.value)
          "#{key}: #{value}"
        end
        "{#{pairs.join(', ')}}"
      end

    when Prism::KeywordHashNode
      # Keyword arguments in method calls (e.g., link_to "text", path, class: "btn")
      if node.elements.empty?
        "{}"
      else
        pairs = node.elements.map do |assoc|
          key = ruby_to_js(assoc.key)
          value = ruby_to_js(assoc.value)
          "#{key}: #{value}"
        end
        "{#{pairs.join(', ')}}"
      end

    when Prism::IfNode
      # Ternary operator
      # Double parentheses to protect from operator precedence issues (e.g., 5 + (cond ? 1 : 0))
      condition = ruby_to_js(node.predicate)
      true_val = node.statements ? ruby_to_js(node.statements.body[0]) : "null"
      false_val = node.subsequent ? ruby_to_js(node.subsequent.statements.body[0]) : "null"
      "((#{condition}) ? #{true_val} : #{false_val})"

    when Prism::ParenthesesNode
      # Just unwrap the parentheses
      ruby_to_js(node.body.body[0])

    when Prism::ConstantReadNode
      # Constant reference like Turbo or JSON
      node.name.to_s

    when Prism::RangeNode
      # Ruby range: 1..10 or 1...10
      # Convert to array generation in JavaScript
      left = ruby_to_js(node.left)
      right = ruby_to_js(node.right)

      # Check if it's exclusive (...)  or inclusive (..)
      if node.exclude_end?
        # Exclusive range: 1...10 -> [1,2,3,...,9]
        "Array.from({length: #{right} - #{left}}, (_, i) => #{left} + i)"
      else
        # Inclusive range: 1..10 -> [1,2,3,...,10]
        "Array.from({length: #{right} - #{left} + 1}, (_, i) => #{left} + i)"
      end

    else
      "/* TODO: #{node.class.name} */"
    end
  end

  def convert_call(node)
    method = node.name.to_s

    # Handle JavaScript globals (console, etc.) when called without receiver
    if node.receiver.nil? && method == "console"
      return "console"
    end

    # Handle Rails helper methods when called without receiver
    if node.receiver.nil? && method == "dom_id"
      args = node.arguments ? node.arguments.arguments.map { |a| ruby_to_js(a) } : []
      return "domId(#{args.join(', ')})"
    end

    # Handle render partial calls
    if node.receiver.nil? && method == "render"
      args = node.arguments ? node.arguments.arguments.map { |a| ruby_to_js(a) } : []
      # Convert Rails partial name to function name
      # e.g., "heat_header" -> heatHeader
      if args.length > 0
        partial_name = args[0].gsub(/^["']|["']$/, '') # Remove quotes
        function_name = partial_name.split('_').map.with_index { |part, i| i == 0 ? part : part.capitalize }.join
        return "#{function_name}(data)"
      end
      return "/* Unknown render call */"
    end

    # Stub Rails view helpers for SPA (navigation will be reimplemented later)
    if node.receiver.nil?
      case method
      when "link_to"
        # link_to text, url, options -> generate <a> tag with attributes
        if node.block
          # link_to(url, options) do ... end -> render block content
          # For now, just return empty string - block will be evaluated separately
          return "''"
        else
          # link_to text, url, options -> generate <a href="url" ...attrs>text</a>
          args = node.arguments ? node.arguments.arguments : []

          text = args.length > 0 ? ruby_to_js(args[0]) : "''"
          href = args.length > 1 ? ruby_to_js(args[1]) : "'#'"

          # Build attributes from options hash (third argument)
          attrs = []
          attrs << "href=\"' + (#{href}) + '\""

          if args.length > 2 && args[2].is_a?(Prism::KeywordHashNode)
            args[2].elements.each do |assoc|
              key_name = case assoc.key
              when Prism::SymbolNode
                assoc.key.unescaped
              when Prism::StringNode
                assoc.key.unescaped
              else
                assoc.key.slice
              end

              value = ruby_to_js(assoc.value)

              # Handle special data attribute (hash)
              if key_name == 'data' && assoc.value.is_a?(Prism::HashNode)
                assoc.value.elements.each do |data_assoc|
                  data_key = case data_assoc.key
                  when Prism::SymbolNode
                    data_assoc.key.unescaped
                  when Prism::StringNode
                    data_assoc.key.unescaped
                  else
                    data_assoc.key.slice
                  end
                  data_value = ruby_to_js(data_assoc.value)
                  attrs << "data-#{data_key}=\"' + #{data_value} + '\""
                end
              else
                attrs << "#{key_name}=\"' + #{value} + '\""
              end
            end
          end

          return "'<a #{attrs.join(' ')}>' + (#{text}) + '</a>'"
        end
      when "image_tag"
        # image_tag src, options -> generate stub <img> tag
        args = node.arguments ? node.arguments.arguments : []
        if args.length > 0
          src = ruby_to_js(args[0])

          # Check for options hash (second argument)
          class_attr = ""
          if args.length > 1 && args[1].is_a?(Prism::KeywordHashNode)
            # Extract class from hash
            args[1].elements.each do |assoc|
              if assoc.is_a?(Prism::AssocNode) && assoc.key.is_a?(Prism::SymbolNode) && assoc.key.unescaped == "class"
                class_value = ruby_to_js(assoc.value)
                class_attr = " class=\"${#{class_value}}\""
                break
              end
            end
          end

          return "`<img#{class_attr} src=\"${#{src}}\" />`"
        else
          return "''"
        end
      when "raw"
        # raw(html) in Rails marks string as safe - in JS just return the string
        args = node.arguments ? node.arguments.arguments.map { |a| ruby_to_js(a) } : []
        if args.length > 0
          return args[0]
        else
          return "''"
        end
      when "judge_heatlist_path", "post_score_path", "start_heat_event_index_path", "toggle_present_person_path", "person_path", "root_path"
        # Path helpers -> return '#' (SPA will handle navigation differently)
        return "'#'"
      when "judge_backs_display", "heat_dance_slot_display", "heat_multi_dance_names"
        # Custom helper methods -> return empty string stub
        return "''"
      end
    end

    receiver = node.receiver ? ruby_to_js(node.receiver) : nil
    args = node.arguments ? node.arguments.arguments.map { |a| ruby_to_js(a) } : []

    # Check for block argument (e.g., &:method_name or {|x| ... })
    if node.block.is_a?(Prism::BlockArgumentNode)
      # Pattern: &:method_name -> x => x.method_name
      if node.block.expression.is_a?(Prism::SymbolNode)
        method_name = node.block.expression.unescaped
        args << "x => x.#{method_name}"
      end
    elsif node.block.is_a?(Prism::BlockNode)
      # Regular block: {|param| body} -> param => body
      # Or numbered parameter: {it...} -> it => body (Ruby 3.4+)
      block_params = node.block.parameters
      param_names = []

      if block_params
        if block_params.is_a?(Prism::ItParametersNode)
          # Numbered parameter: `it` is the implicit parameter name
          param_names = ['it']
        elsif block_params.parameters
          # Traditional block parameters: |x, y|
          param_nodes = block_params.parameters.requireds || []
          param_names = param_nodes.map(&:name)
        end
      end

      # Convert block body to JavaScript expression
      if node.block.body && node.block.body.body && node.block.body.body.length > 0
        # For now, handle single-expression blocks
        block_body = node.block.body.body.first
        body_js = ruby_to_js(block_body)

        if param_names.empty?
          args << "() => #{body_js}"
        else
          args << "#{param_names.join(', ')} => #{body_js}"
        end
      end
    end

    # Check for safe navigation
    flags = node.instance_variable_get(:@flags)
    is_safe_nav = (flags & Prism::CallNodeFlags::SAFE_NAVIGATION) != 0
    is_var_call = (flags & Prism::CallNodeFlags::VARIABLE_CALL) != 0
    op = is_safe_nav ? "?." : "."

    # Special method conversions
    case method
    when "[]"
      "#{receiver}[#{args[0]}]"
    when "[]="
      # Array/hash assignment: arr[index] = value
      "#{receiver}[#{args[0]}] = #{args[1]}"
    when "<<"
      # Array append: arr << item -> arr.push(item)
      "#{receiver}.push(#{args[0]})"
    when "=="
      "#{receiver} == #{args[0]}"
    when "!="
      "#{receiver} != #{args[0]}"
    when "<"
      "#{receiver} < #{args[0]}"
    when "<="
      "#{receiver} <= #{args[0]}"
    when ">"
      "#{receiver} > #{args[0]}"
    when ">="
      "#{receiver} >= #{args[0]}"
    when "+"
      "#{receiver} + #{args[0]}"
    when "-"
      "#{receiver} - #{args[0]}"
    when "*"
      "#{receiver} * #{args[0]}"
    when "/"
      "#{receiver} / #{args[0]}"
    when "blank?"
      "#{receiver} == null || #{receiver}.length === 0"
    when "present?"
      "#{receiver} != null && #{receiver}.length > 0"
    when "empty?"
      "(#{receiver}.length === 0)"
    when "any?"
      "#{receiver}.length > 0"
    when "nil?"
      "#{receiver} == null"
    when "include?"
      "#{receiver}.includes(#{args.join(', ')})"
    when "start_with?"
      "#{receiver}.startsWith(#{args.join(', ')})"
    when "length", "size"
      "#{receiver}.length"
    when "to_s"
      "String(#{receiver})"
    when "first"
      "#{receiver}[0]"
    when "last"
      "#{receiver}[#{receiver}.length - 1]"
    when "max"
      "Math.max(...#{receiver})"
    when "min"
      "Math.min(...#{receiver})"
    when "keys"
      "Object.keys(#{receiver})"
    when "respond_to?"
      # Check if object has a method/property
      # respond_to?(:method) -> 'method' in receiver
      if args.length == 1
        # Ensure the method name is a quoted string
        method_name = args[0]
        # If it doesn't have quotes, add them (shouldn't happen with proper conversion)
        method_name = "\"#{method_name}\"" unless method_name.start_with?('"', "'")
        "#{method_name} in #{receiver}"
      else
        "#{receiver}.respond_to?(#{args.join(', ')})"  # Fallback
      end
    when "gsub"
      "#{receiver}.replace(#{args.join(', ')})"
    when "map!"
      # Mutating map - JavaScript doesn't have this, use regular map
      # Note: This will be used in an assignment context
      "#{receiver}.map(#{args.join(', ')})"
    when "!"
      # Unary not
      "!#{receiver}"
    else
      if receiver
        # Strip trailing ? from boolean methods (e.g., assign_judges? -> assign_judges)
        js_method = method.to_s.end_with?('?') ? method.to_s.chomp('?') : method.to_s

        if args.empty?
          "#{receiver}#{op}#{js_method}"
        else
          "#{receiver}#{op}#{js_method}(#{args.join(', ')})"
        end
      elsif is_var_call && args.empty?
        # Bare identifier - check if it's local or data
        if @local_vars.include?(method.to_sym)
          method
        else
          "data.#{method}"
        end
      else
        "#{method}(#{args.join(', ')})"
      end
    end
  end

  def add_html(text)
    return if text.empty?
    # Escape for template literal
    escaped = escape_template_literal(text)
    add_line("html += `#{escaped}`;")
  end

  def add_output(expr)
    # Wrap expression to handle nil/undefined, but ensure proper precedence
    # Use || instead of ?? to avoid precedence issues with existing || in expr
    add_line("html += (#{expr}) || '';")
  end

  def add_line(code)
    level = [@indent_level, 0].max
    @lines << ("  " * level) + code
  end

  def escape_template_literal(text)
    text.gsub('\\', '\\\\\\\\').gsub('`', '\\`').gsub('${', '\\${')
  end

  def escape_js_string(text)
    text.gsub('\\', '\\\\').gsub('"', '\\"').gsub("\n", '\\n').gsub("\r", '\\r')
  end

  def compile_with_rails_handler(template_source)
    # Use Rails' ERB handler which produces valid Ruby with @output_buffer
    require 'action_view'

    template = ActionView::Template.new(
      template_source,
      'template',
      ActionView::Template.handler_for_extension(:erb),
      format: :html,
      locals: []
    )

    handler = ActionView::Template::Handlers::ERB.new
    handler.call(template, template_source)
  end
end
