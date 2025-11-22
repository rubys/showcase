#!/usr/bin/env ruby
# frozen_string_literal: true

# Explore how ERB compiles to Ruby, and whether Prism can parse the result
require 'erb'
require 'prism'

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
puts "Exploring ERB Compilation to Ruby"
puts "=" * 80
puts
puts "Original ERB template:"
puts "-" * 80
puts SIMPLE_TEMPLATE
puts "-" * 80
puts

# Compile ERB to Ruby code
erb = ERB.new(SIMPLE_TEMPLATE, trim_mode: '-')
ruby_code = erb.src

puts "Compiled Ruby code:"
puts "-" * 80
puts ruby_code
puts "-" * 80
puts

# Try to parse the compiled Ruby with Prism
puts "Parsing compiled Ruby with Prism:"
puts "-" * 80

result = Prism.parse(ruby_code)

if result.success?
  puts "✅ Prism successfully parsed the compiled ERB!"
  puts
  puts "AST root: #{result.value.class.name}"
  puts "Statements count: #{result.value.statements.body.length}"
  puts

  # Show a simplified view of the AST
  puts "Simplified AST structure:"
  result.value.statements.body.each_with_index do |stmt, i|
    puts "  Statement #{i + 1}: #{stmt.class.name}"
    case stmt
    when Prism::LocalVariableWriteNode
      puts "    - Assigns to: #{stmt.name}"
    when Prism::CallNode
      puts "    - Calls: #{stmt.name}"
    when Prism::IfNode
      puts "    - If statement"
    end
  end
else
  puts "❌ Prism failed to parse"
  puts "Errors:"
  result.errors.each { |err| puts "  - #{err.message}" }
end

puts
puts "=" * 80
puts "Testing with actual template"
puts "=" * 80
puts

# Try with one of our actual templates
template_path = "app/views/scores/_table_heat.html.erb"
if File.exist?(template_path)
  template_content = File.read(template_path)

  puts "Template: #{template_path}"
  puts "Size: #{template_content.bytesize} bytes"
  puts

  erb = ERB.new(template_content, trim_mode: '-')
  compiled_ruby = erb.src

  puts "Compiled Ruby code size: #{compiled_ruby.bytesize} bytes"
  puts "Compiled Ruby lines: #{compiled_ruby.lines.count}"
  puts
  puts "First 50 lines of compiled Ruby:"
  puts "-" * 80
  puts compiled_ruby.lines.take(50).join
  puts "-" * 80
  puts

  result = Prism.parse(compiled_ruby)

  if result.success?
    puts "✅ Prism successfully parsed the compiled template!"
    puts "Statements count: #{result.value.statements.body.length}"
  else
    puts "❌ Prism failed to parse"
    puts "Errors (first 5):"
    result.errors.take(5).each { |err| puts "  - #{err.message}" }
  end
end
