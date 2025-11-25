#!/usr/bin/env ruby
# frozen_string_literal: true

# Detailed exploration of Herb's AST node properties
require 'herb'

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

def explore_node_properties(node, depth = 0, max_depth = 5)
  return if depth > max_depth

  indent = "  " * depth
  node_type = node.class.name.split('::').last

  puts "#{indent}#{node_type}"

  # Get all instance variables
  ivars = node.instance_variables
  unless ivars.empty?
    ivars.each do |ivar|
      value = node.instance_variable_get(ivar)
      next if value.is_a?(Array) || value.is_a?(Hash) || value.respond_to?(:children)

      # Show primitive values and tokens
      if value.is_a?(String)
        preview = value.strip[0..60]
        preview += "..." if value.strip.length > 60
        puts "#{indent}  #{ivar}: #{preview.inspect}"
      elsif value.is_a?(Herb::Token)
        puts "#{indent}  #{ivar}: Token(#{value.value.inspect})"
      elsif value.nil? || value.is_a?(TrueClass) || value.is_a?(FalseClass) || value.is_a?(Numeric)
        puts "#{indent}  #{ivar}: #{value.inspect}"
      end
    end
  end

  # Recurse into children
  if node.respond_to?(:children) && node.children
    node.children.each { |child| explore_node_properties(child, depth + 1, max_depth) }
  elsif node.instance_variable_defined?(:@body) && node.instance_variable_get(:@body).is_a?(Array)
    node.instance_variable_get(:@body).each { |child| explore_node_properties(child, depth + 1, max_depth) }
  end
end

puts "=" * 80
puts "Detailed Herb AST Exploration"
puts "=" * 80
puts

result = Herb.parse(SIMPLE_TEMPLATE)

if result.failed?
  puts "Parse failed: #{result.errors.inspect}"
  exit 1
end

ast = result.value
explore_node_properties(ast)
