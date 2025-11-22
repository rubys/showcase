#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to explore Herb's ERB parser API
# Usage: ruby script/explore_herb.rb [path/to/template.html.erb]

require 'herb'
require 'json'

# Simple ERB template for testing
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

def explore_herb_api
  puts "=" * 80
  puts "Exploring Herb ERB Parser API"
  puts "=" * 80
  puts

  # Check what methods are available
  puts "Available Herb methods:"
  puts Herb.methods.grep_v(/^_/).sort.join(", ")
  puts

  # Try parsing a simple template
  puts "Parsing simple template..."
  puts "-" * 80
  puts SIMPLE_TEMPLATE
  puts "-" * 80
  puts

  begin
    result = Herb.parse(SIMPLE_TEMPLATE)

    puts "Parse result class: #{result.class}"
    puts "Parse result methods: #{result.methods.grep_v(/^_/).sort.take(20).join(', ')}"
    puts

    # Check if parsing was successful
    if result.failed?
      puts "Parsing failed!"
      puts "Errors: #{result.errors.inspect}"
      return
    end

    # Get the actual AST node
    ast = result.value
    puts "AST node class: #{ast.class}"
    puts

    # Explore the AST structure
    puts "\nAST Structure (focusing on ERB nodes):"
    puts "-" * 80
    explore_node(ast, 0)
    puts "-" * 80

  rescue => e
    puts "Error parsing: #{e.message}"
    puts e.backtrace.first(5)
  end
end

def explore_node(node, depth, max_depth: 10)
  return if depth > max_depth

  indent = "  " * depth

  # Show node type
  node_type = node.class.name.split('::').last
  puts "#{indent}#{node_type}"

  # Show all available methods for this node type
  node_methods = (node.methods - Object.methods).grep_v(/^_/).sort

  # For ERB nodes, show the Ruby code content
  case node_type
  when 'ERBIfNode'
    puts "#{indent}  condition: #{node.condition.inspect}" if node.respond_to?(:condition)
  when 'ERBBlockNode'
    puts "#{indent}  keyword: #{node.keyword.inspect}" if node.respond_to?(:keyword)
    puts "#{indent}  code: #{node.code.inspect}" if node.respond_to?(:code)
  when 'ERBContentNode'
    puts "#{indent}  code: #{node.code.inspect}" if node.respond_to?(:code)
    puts "#{indent}  escaped?: #{node.escaped?}" if node.respond_to?(:escaped?)
  when 'ERBElsifNode'
    puts "#{indent}  condition: #{node.condition.inspect}" if node.respond_to?(:condition)
  when 'ERBElseNode'
    # No special properties
  when 'HTMLTextNode'
    content = node.content if node.respond_to?(:content)
    if content && !content.strip.empty?
      preview = content.strip[0..50]
      preview += "..." if content.strip.length > 50
      puts "#{indent}  content: #{preview.inspect}"
    end
  end

  # For HTML elements, show tag name
  if node.respond_to?(:tag_name) && node.tag_name.is_a?(String)
    puts "#{indent}  tag: <#{node.tag_name}>"
  end

  # Recurse into children
  if node.respond_to?(:children) && node.children
    node.children.each { |child| explore_node(child, depth + 1, max_depth: max_depth) }
  elsif node.respond_to?(:body) && node.body.is_a?(Array)
    node.body.each { |child| explore_node(child, depth + 1, max_depth: max_depth) }
  end
end

def explore_template_file(file_path)
  puts "\n" + "=" * 80
  puts "Parsing file: #{file_path}"
  puts "=" * 80
  puts

  unless File.exist?(file_path)
    puts "File not found: #{file_path}"
    return
  end

  content = File.read(file_path)
  puts "File size: #{content.bytesize} bytes"
  puts "Lines: #{content.lines.count}"
  puts

  begin
    result = Herb.parse_file(file_path)

    puts "Parse successful!"
    puts "Result class: #{result.class}"
    puts

    # Try to get AST info
    if result.respond_to?(:inspect)
      inspection = result.inspect
      puts "Inspection (first 500 chars):"
      puts inspection[0, 500]
      puts "..." if inspection.length > 500
    end

  rescue => e
    puts "Error parsing file: #{e.message}"
    puts e.backtrace.first(5)
  end
end

def try_cli_commands(file_path)
  puts "\n" + "=" * 80
  puts "Testing Herb CLI commands"
  puts "=" * 80
  puts

  # Try the parse command
  puts "$ herb parse #{file_path}"
  system("herb", "parse", file_path)
  puts

  # Try the ruby command
  puts "$ herb ruby #{file_path}"
  system("herb", "ruby", file_path)
  puts
end

# Main execution
if ARGV[0]
  # Parse specific file
  file_path = ARGV[0]
  explore_template_file(file_path)
  try_cli_commands(file_path)
else
  # Explore API with simple template
  explore_herb_api

  # Try with one of our actual templates
  template_path = "app/views/scores/_table_heat.html.erb"
  if File.exist?(template_path)
    explore_template_file(template_path)
  end
end
