#!/usr/bin/env ruby
# frozen_string_literal: true

# Prototype: Convert Ruby expressions to JavaScript using Prism AST
require 'prism'

class PrismToJsConverter
  def convert(ruby_expr)
    result = Prism.parse(ruby_expr)

    unless result.success?
      # For incomplete expressions (like blocks), fall back to regex
      return nil
    end

    # Get the first statement from the AST
    statements = result.value.statements
    return "" if statements.nil? || statements.body.empty?

    node = statements.body[0]
    convert_node(node)
  end

  private

  def convert_node(node)
    case node
    when Prism::InstanceVariableReadNode
      # @var -> data.var
      "data.#{node.name.to_s.delete_prefix('@')}"

    when Prism::CallNode
      convert_call_node(node)

    when Prism::LocalVariableTargetNode
      # Variable being assigned to
      node.name.to_s

    when Prism::LocalVariableReadNode
      # Local variable reference
      node.name.to_s

    when Prism::LocalVariableWriteNode
      # var = value
      "const #{node.name} = #{convert_node(node.value)}"

    when Prism::StringNode
      # "string"
      "\"#{node.unescaped}\""

    when Prism::InterpolatedStringNode
      # "string #{expr}" -> `string ${expr}`
      parts = node.parts.map do |part|
        if part.is_a?(Prism::StringNode)
          part.unescaped
        else
          # EmbeddedStatementsNode or similar
          "${#{convert_node(part.statements.body[0])}}"
        end
      end
      "`#{parts.join}`"

    when Prism::SymbolNode
      # :symbol -> 'symbol'
      "'#{node.unescaped}'"

    when Prism::ArrayNode
      # [1, 2, 3] or %w(a b c)
      elements = node.elements.map { |el| convert_node(el) }
      "[#{elements.join(', ')}]"

    when Prism::HashNode
      # {key: value}
      if node.elements.empty?
        "{}"
      else
        pairs = node.elements.map do |pair|
          key = convert_node(pair.key)
          value = convert_node(pair.value)
          "#{key}: #{value}"
        end
        "{#{pairs.join(', ')}}"
      end

    when Prism::IfNode
      # Ternary: condition ? true_value : false_value
      condition = convert_node(node.predicate)
      true_val = node.statements ? convert_node(node.statements.body[0]) : "null"
      false_val = node.consequent ? convert_node(node.consequent.statements.body[0]) : "null"
      "(#{condition}) ? #{true_val} : #{false_val}"

    when Prism::CallAndWriteNode
      # a &&= b -> a = a && b
      "#{node.name} = #{node.name} && #{convert_node(node.value)}"

    when Prism::NilNode
      "null"

    when Prism::TrueNode
      "true"

    when Prism::FalseNode
      "false"

    when Prism::IntegerNode
      node.value.to_s

    else
      # Unknown node type - return placeholder
      "/* TODO: #{node.class.name} */"
    end
  end

  def convert_call_node(node)
    # Handle receiver (the object being called on)
    receiver = if node.receiver
      convert_node(node.receiver)
    else
      nil
    end

    method_name = node.name.to_s

    # Check for safe navigation
    # Prism uses instance variable @flags as a bitmask
    operator = if node.instance_variable_get(:@flags) & Prism::CallNodeFlags::SAFE_NAVIGATION != 0
      "?."
    elsif receiver
      "."
    else
      ""
    end

    # Handle arguments
    args = if node.arguments
      node.arguments.arguments.map { |arg| convert_node(arg) }
    else
      []
    end

    # Special method conversions
    case method_name
    when "[]"
      # Array/hash access: obj[key]
      "#{receiver}[#{args[0]}]"

    when "blank?"
      # .blank? -> == null || .length === 0
      "#{receiver} == null || #{receiver}.length === 0"

    when "empty?"
      # .empty? -> .length === 0
      "#{receiver}.length === 0"

    when "nil?"
      # .nil? -> == null
      "#{receiver} == null"

    when "include?"
      # .include?(x) -> .includes(x)
      "#{receiver}.includes(#{args.join(', ')})"

    when "first"
      # .first -> [0]
      "#{receiver}[0]"

    when "last"
      # .last -> [length - 1]
      "#{receiver}[#{receiver}.length - 1]"

    when "keys"
      # .keys -> Object.keys()
      "Object.keys(#{receiver})"

    when "start_with?"
      # .start_with?(x) -> .startsWith(x)
      "#{receiver}.startsWith(#{args.join(', ')})"

    when "to_s"
      # .to_s -> String()
      "String(#{receiver})"

    when "each"
      # This is complex - handled separately in ERBBlockNode
      if receiver
        "#{receiver}.forEach" # Simplified
      else
        "forEach"
      end

    else
      # Regular method call
      if receiver
        if args.empty?
          "#{receiver}#{operator}#{method_name}"
        else
          "#{receiver}#{operator}#{method_name}(#{args.join(', ')})"
        end
      else
        # Check if it's a variable call (no parens needed)
        flags = node.instance_variable_get(:@flags)
        is_variable_call = (flags & Prism::CallNodeFlags::VARIABLE_CALL) != 0

        if is_variable_call && args.empty?
          # Just the identifier, no parens
          method_name
        else
          # Function call with parens
          "#{method_name}(#{args.join(', ')})"
        end
      end
    end
  end
end

# Test the converter
puts "=" * 80
puts "Prism-based Ruby to JavaScript Converter"
puts "=" * 80
puts

TEST_CASES = {
  "@title" => "data.title",
  "subject.entry.lead.back.number" => "data.subject.entry.lead.back.number",
  "@results[score]" => "data.results[score]",
  "params[:style]" => "params['style']",
  "@results.keys.first" => "Object.keys(data.results)[0]",
  "subject.entry.lead.back.blank?" => "data.subject.entry.lead.back == null || data.subject.entry.lead.back.length === 0",
  "%w(Solo Jack and Jill)" => "['Solo', 'Jack', 'and', 'Jill']",
  "options = @results.keys.first" => "const options = Object.keys(data.results)[0]",
}

converter = PrismToJsConverter.new

TEST_CASES.each do |ruby, expected_js|
  puts "Ruby:     #{ruby}"
  actual_js = converter.convert(ruby)
  puts "Expected: #{expected_js}"
  puts "Actual:   #{actual_js}"

  if actual_js == expected_js
    puts "✅ PASS"
  else
    puts "❌ FAIL"
  end
  puts
end
