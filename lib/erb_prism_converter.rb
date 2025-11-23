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
    # Step 1: Compile ERB to Ruby
    erb = ERB.new(@template, trim_mode: '-')
    ruby_code = erb.src

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
      # Scan each loops for assignments in their bodies
      if stmt.name == :each && stmt.block
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

    when Prism::NextNode
      # Ruby 'next' in a loop → JavaScript 'continue'
      add_line("continue;")

    else
      add_line("// TODO: #{stmt.class.name}")
    end
  end

  def process_call_statement(node)
    # Check if this is _erbout.<< ... (output statement)
    if node.name == :<<
      if node.receiver.is_a?(Prism::LocalVariableReadNode) && node.receiver.name == :_erbout
        process_output(node.arguments.arguments[0])
        return
      end
    end

    # Check if this is a .each loop at statement level
    if node.name == :each && node.block
      process_each_loop(node)
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
      if arg.name == :to_s && arg.receiver.is_a?(Prism::ParenthesesNode)
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
      else
        # each with multiple params (hash iteration, each_with_index, etc.)
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

    when Prism::IfNode
      # Ternary operator
      condition = ruby_to_js(node.predicate)
      true_val = node.statements ? ruby_to_js(node.statements.body[0]) : "null"
      false_val = node.subsequent ? ruby_to_js(node.subsequent.statements.body[0]) : "null"
      "(#{condition}) ? #{true_val} : #{false_val}"

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
      block_params = node.block.parameters
      param_names = []

      if block_params && block_params.parameters
        param_nodes = block_params.parameters.requireds || []
        param_names = param_nodes.map(&:name)
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
        if args.empty?
          "#{receiver}#{op}#{method}"
        else
          "#{receiver}#{op}#{method}(#{args.join(', ')})"
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
end
