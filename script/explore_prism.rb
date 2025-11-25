#!/usr/bin/env ruby
# frozen_string_literal: true

# Explore Prism (Ruby's official parser) for parsing Ruby expressions
require 'prism'

# Test expressions from our ERB templates
TEST_EXPRESSIONS = {
  "Simple instance variable" => "@title",
  "Method chain" => "subject.entry.lead.back.number",
  "Safe navigation" => "@results[score]&.each",
  "Array access with safe nav" => "@results[score]&.first",
  "Hash access with symbol" => "params[:style]",
  "Method with block" => "@items.each do |item|",
  "Complex ternary" => "@results.keys.first.start_with?('{') ? JSON.parse(@results.keys.first) : {}",
  "Boolean with .blank?" => "!subject.entry.lead.back.blank?",
  "Boolean logic" => "!subject.category.include? 'Newcomer' and !subject.entry.lead.back.blank?",
  "Rails path helper" => "update_rank_path(judge: @judge)",
  "Array word syntax" => "%w(Solo Jack and Jill)",
  "String interpolation" => "\"Heat #{@number}\"",
  "Assignment" => "options = @results.keys.first"
}

def explore_expression(name, expr)
  puts "=" * 80
  puts name
  puts "-" * 80
  puts "Expression: #{expr.inspect}"
  puts

  begin
    result = Prism.parse(expr)

    puts "Parse result class: #{result.class}"
    puts "Success: #{result.success?}"
    puts "Errors: #{result.errors.map(&:message)}" if result.errors.any?
    puts "Warnings: #{result.warnings.map(&:message)}" if result.warnings.any?
    puts

    if result.success?
      # Show the AST
      puts "AST (first 500 chars):"
      ast_inspect = result.value.inspect
      puts ast_inspect[0, 500]
      puts "..." if ast_inspect.length > 500
      puts

      # Show the node type
      puts "Root node type: #{result.value.class.name}"

      # Show statements
      if result.value.respond_to?(:statements)
        statements = result.value.statements
        puts "Statements: #{statements.class.name}"
        if statements.respond_to?(:body)
          body = statements.body
          puts "Statement count: #{body.length}"
          if body.length > 0
            first_stmt = body[0]
            puts "First statement type: #{first_stmt.class.name}"
            puts "First statement inspect: #{first_stmt.inspect[0, 200]}"
          end
        end
      end
    end

  rescue => e
    puts "Error: #{e.class.name}: #{e.message}"
    puts e.backtrace.first(3)
  end

  puts
end

TEST_EXPRESSIONS.each do |name, expr|
  explore_expression(name, expr)
end

puts "=" * 80
puts "Prism Node Type Reference"
puts "=" * 80
puts
puts "Common node types we'll encounter:"
puts "- InstanceVariableReadNode: @variable"
puts "- CallNode: method calls like .each, .blank?, etc."
puts "- SymbolNode: :symbol"
puts "- StringNode: \"string\""
puts "- InterpolatedStringNode: \"string \#{expr}\""
puts "- IfNode: ternary operator (? :)"
puts "- AndNode, OrNode: && and ||"
puts "- NotNode: ! operator"
puts "- ArrayNode: [1, 2, 3] or %w(a b c)"
puts "- HashNode: {key: value}"
puts "- LocalVariableWriteNode: var = value"
puts "- BlockNode: do |x| ... end"
puts
puts "Visit https://ruby.github.io/prism/ for complete documentation"
