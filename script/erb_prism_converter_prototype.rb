#!/usr/bin/env ruby
# frozen_string_literal: true

# Prototype: Convert ERB → Ruby → Prism AST → JavaScript
require 'erb'
require 'prism'

class ErbPrismConverter
  def initialize(template)
    @template = template
    @lines = []
    @indent_level = 2
  end

  def convert
    # Step 1: Compile ERB to Ruby
    erb = ERB.new(@template, trim_mode: '-')
    ruby_code = erb.src

    # Step 2: Parse Ruby with Prism
    result = Prism.parse(ruby_code)

    unless result.success?
      raise "Failed to parse compiled ERB: #{result.errors.map(&:message).join(', ')}"
    end

    # Step 3: Generate JavaScript
    @lines << "export function render(data) {"
    @lines << "  let html = '';"
    @lines << ""

    # Process each statement in the compiled Ruby
    result.value.statements.body.each do |stmt|
      process_statement(stmt)
    end

    @lines << ""
    @lines << "  return html;"
    @lines << "}"

    @lines.join("\n")
  end

  private

  def process_statement(stmt)
    case stmt
    when Prism::LocalVariableWriteNode
      # _erbout = +'' → skip (we use 'html' instead)
      return if stmt.name == :_erbout

    when Prism::CallNode
      process_call_node(stmt)

    when Prism::IfNode
      process_if_node(stmt)

    when Prism::UnlessNode
      process_unless_node(stmt)

    when Prism::LocalVariableReadNode
      # Final _erbout → skip (we return html)
      return if stmt.name == :_erbout

    else
      add_line("// TODO: #{stmt.class.name}")
    end
  end

  def process_call_node(node)
    # Check if this is _erbout.<< ...
    return unless node.name == :<<
    return unless node.receiver.is_a?(Prism::LocalVariableReadNode)
    return unless node.receiver.name == :_erbout

    # Get the argument
    arg = node.arguments.arguments[0]

    case arg
    when Prism::StringNode
      # Static HTML: _erbout.<< "text".freeze
      add_html(arg.unescaped)

    when Prism::CallNode
      # Dynamic output: _erbout.<<(( expr ).to_s)
      # The pattern is: <<( CallNode[to_s] with ParenthesesNode receiver )
      if arg.name == :to_s && arg.receiver.is_a?(Prism::ParenthesesNode)
        # Extract the expression inside the double parens
        # ParenthesesNode.body is a StatementsNode
        inner_stmt = arg.receiver.body.body[0]
        js_expr = ruby_to_js(inner_stmt)
        add_output(js_expr)
      else
        # Could be string interpolation or other complex case
        js_expr = ruby_to_js(arg)
        add_output(js_expr)
      end

    else
      # Other cases
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

    # Process elsif/else
    if node.consequent
      case node.consequent
      when Prism::ElseNode
        @indent_level -= 1
        add_line("} else {")
        @indent_level += 1
        node.consequent.statements&.body&.each { |stmt| process_statement(stmt) }
      when Prism::IfNode
        @indent_level -= 1
        condition = ruby_to_js(node.consequent.predicate)
        add_line("} else if (#{condition}) {")
        @indent_level += 1
        node.consequent.statements&.body&.each { |stmt| process_statement(stmt) }
        # TODO: Handle nested consequents
      end
    end

    @indent_level -= 1
    add_line("}")
  end

  def process_unless_node(node)
    condition = ruby_to_js(node.predicate)
    add_line("if (!(#{condition})) {")
    @indent_level += 1

    node.statements&.body&.each { |stmt| process_statement(stmt) }

    @indent_level -= 1
    add_line("}")
  end

  def ruby_to_js(node)
    case node
    when Prism::InstanceVariableReadNode
      "data.#{node.name.to_s.delete_prefix('@')}"

    when Prism::CallNode
      convert_call(node)

    when Prism::LocalVariableReadNode
      node.name.to_s

    when Prism::StringNode
      "\"#{node.unescaped}\""

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

    when Prism::ArrayNode
      elements = node.elements.map { |el| ruby_to_js(el) }
      "[#{elements.join(', ')}]"

    else
      "/* TODO: #{node.class.name} */"
    end
  end

  def convert_call(node)
    receiver = node.receiver ? ruby_to_js(node.receiver) : nil
    method = node.name.to_s
    args = node.arguments ? node.arguments.arguments.map { |a| ruby_to_js(a) } : []

    # Check for safe navigation
    flags = node.instance_variable_get(:@flags)
    is_safe_nav = (flags & Prism::CallNodeFlags::SAFE_NAVIGATION) != 0
    is_var_call = (flags & Prism::CallNodeFlags::VARIABLE_CALL) != 0
    op = is_safe_nav ? "?." : "."

    # Method conversions
    case method
    when "[]"
      "#{receiver}[#{args[0]}]"
    when "blank?"
      "#{receiver} == null || #{receiver}.length === 0"
    when "empty?"
      "#{receiver}.length === 0"
    when "nil?"
      "#{receiver} == null"
    when "include?"
      "#{receiver}.includes(#{args.join(', ')})"
    when "length"
      "#{receiver}.length"
    when "to_s"
      "String(#{receiver})"
    else
      if receiver
        if args.empty?
          "#{receiver}#{op}#{method}"
        else
          "#{receiver}#{op}#{method}(#{args.join(', ')})"
        end
      elsif is_var_call && args.empty?
        method
      else
        "#{method}(#{args.join(', ')})"
      end
    end
  end

  def add_html(text)
    return if text.empty?
    escaped = text.gsub('\\', '\\\\\\\\').gsub('`', '\\`').gsub('${', '\\${')
    add_line("html += `#{escaped}`;")
  end

  def add_output(expr)
    add_line("html += (#{expr} ?? '');")
  end

  def add_line(code)
    @lines << ("  " * @indent_level) + code
  end
end

# Test
SIMPLE_TEMPLATE = <<~ERB
  <div class="container">
    <% if @show_header %>
      <h1><%= @title %></h1>
    <% end %>
    <% @items.each do |item| %>
      <div class="item"><%= item.name %></div>
    <% end %>
  </div>
ERB

puts "=" * 80
puts "ERB → Ruby → Prism AST → JavaScript Converter"
puts "=" * 80
puts
puts "Input ERB:"
puts "-" * 80
puts SIMPLE_TEMPLATE
puts "-" * 80
puts
puts "Output JavaScript:"
puts "-" * 80

converter = ErbPrismConverter.new(SIMPLE_TEMPLATE)
puts converter.convert

puts "-" * 80
