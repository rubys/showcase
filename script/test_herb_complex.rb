#!/usr/bin/env ruby
# frozen_string_literal: true

# Test how Herb handles complex Ruby patterns from our actual templates
require 'herb'

# Problematic patterns from the actual templates
COMPLEX_PATTERNS = <<~ERB
  <div>
    <!-- Safe navigation with each -->
    <% @results[score]&.each do |result| %>
      <div><%= result.name %></div>
    <% end %>

    <!-- params hash access -->
    <div class="<%= params[:style] %>"></div>

    <!-- Complex ternary with object literal -->
    <% options = @results.keys.first.start_with?('{') ? JSON.parse(@results.keys.first) : {} %>

    <!-- Nested method chains -->
    <% if subject.entry.lead.back %>
      <%= subject.entry.lead.back.number %>
    <% end %>

    <!-- Rails path helper -->
    <form action="<%= update_rank_path(judge: @judge) %>" method="post"></form>

    <!-- Boolean logic with .blank? -->
    <% if !subject.category.include? 'Newcomer' and !subject.entry.lead.back.blank? %>
      <span>Valid</span>
    <% end %>

    <!-- Array word syntax -->
    <% %w(Solo Jack\ and\ Jill).each do |cat| %>
      <li><%= cat %></li>
    <% end %>
  </div>
ERB

def show_erb_nodes(node, depth = 0, max_depth = 10)
  return if depth > max_depth

  indent = "  " * depth
  node_type = node.class.name.split('::').last

  # Only show ERB nodes and their Ruby code
  if node_type.start_with?('ERB')
    puts "#{indent}#{node_type}"

    if node.instance_variable_defined?(:@content)
      content_token = node.instance_variable_get(:@content)
      if content_token
        code = content_token.value.strip
        puts "#{indent}  Ruby code: #{code.inspect}"
      end
    end
  end

  # Recurse
  if node.respond_to?(:children) && node.children
    node.children.each { |child| show_erb_nodes(child, depth + 1, max_depth) }
  elsif node.instance_variable_defined?(:@body)
    body = node.instance_variable_get(:@body)
    body.each { |child| show_erb_nodes(child, depth + 1, max_depth) } if body.is_a?(Array)
  end
end

puts "=" * 80
puts "Testing Herb with Complex Ruby Patterns"
puts "=" * 80
puts

result = Herb.parse(COMPLEX_PATTERNS)

if result.failed?
  puts "Parse failed!"
  puts "Errors:"
  result.errors.each { |error| puts "  #{error}" }
  exit 1
end

puts "Parse successful!"
puts
puts "ERB Nodes and Ruby Code:"
puts "-" * 80

ast = result.value
show_erb_nodes(ast)

puts "-" * 80
puts
puts "Key observations:"
puts "1. Herb successfully parses all ERB tags"
puts "2. Ruby code is preserved exactly as written (with whitespace)"
puts "3. Herb doesn't parse the Ruby code itself - just extracts it"
puts "4. We'll need Prism to understand and convert the Ruby expressions"
