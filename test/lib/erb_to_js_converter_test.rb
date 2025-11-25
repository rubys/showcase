# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/erb_to_js_converter"

class ErbToJsConverterTest < ActiveSupport::TestCase
  def convert(erb)
    ErbToJsConverter.new(erb).convert
  end

  test "converts plain HTML" do
    erb = "<div>Hello World</div>"
    js = convert(erb)

    assert_includes js, "html += `<div>Hello World</div>`;"
  end

  test "converts output expressions" do
    erb = "<p><%= name %></p>"
    js = convert(erb)

    assert_includes js, "html += (name ?? '');"
  end

  test "converts instance variables to data properties" do
    erb = "<p><%= @title %></p>"
    js = convert(erb)

    assert_includes js, "html += (data.title ?? '');"
  end

  test "converts if statement" do
    erb = <<~ERB
      <% if active %>
      <p>Active</p>
      <% end %>
    ERB
    js = convert(erb)

    assert_includes js, "if (active) {"
    assert_includes js, "<p>Active</p>"
    assert_includes js, "}"
  end

  test "converts unless statement" do
    erb = <<~ERB
      <% unless hidden %>
      <p>Visible</p>
      <% end %>
    ERB
    js = convert(erb)

    assert_includes js, "if (!(hidden)) {"
    assert_includes js, "<p>Visible</p>"
  end

  test "converts if-else statement" do
    erb = <<~ERB
      <% if online %>
      <p>Online</p>
      <% else %>
      <p>Offline</p>
      <% end %>
    ERB
    js = convert(erb)

    assert_includes js, "if (online) {"
    assert_includes js, "} else {"
  end

  test "converts if-elsif-else statement" do
    erb = <<~ERB
      <% if status == 'good' %>
      <p>Good</p>
      <% elsif status == 'ok' %>
      <p>OK</p>
      <% else %>
      <p>Bad</p>
      <% end %>
    ERB
    js = convert(erb)

    assert_includes js, "if (status == 'good') {"
    assert_includes js, "} else if (status == 'ok') {"
    assert_includes js, "} else {"
  end

  test "converts each loop with single variable" do
    erb = <<~ERB
      <% items.each do |item| %>
      <li><%= item %></li>
      <% end %>
    ERB
    js = convert(erb)

    assert_includes js, "for (const item of items) {"
    assert_includes js, "html += (item ?? '');"
  end

  test "converts each loop with multiple variables" do
    erb = <<~ERB
      <% scores.each do |key, value| %>
      <p><%= key %>: <%= value %></p>
      <% end %>
    ERB
    js = convert(erb)

    assert_includes js, "for (const [key, value] of Object.entries(scores)) {"
  end

  test "converts variable assignment" do
    erb = <<~ERB
      <% total = 100 %>
      <p><%= total %></p>
    ERB
    js = convert(erb)

    assert_includes js, "const total = 100;"
  end

  test "converts next if statement" do
    erb = <<~ERB
      <% items.each do |item| %>
      <% next if item.blank? %>
      <li><%= item %></li>
      <% end %>
    ERB
    js = convert(erb)

    assert_includes js, "if (item == null || item.length === 0) continue;"
  end

  test "converts safe navigation operator" do
    erb = "<%= user&.name %>"
    js = convert(erb)

    assert_includes js, "html += (user?.name ?? '');"
  end

  test "converts blank? method" do
    erb = "<% if title.blank? %><p>No title</p><% end %>"
    js = convert(erb)

    assert_includes js, "if (title == null || title.length === 0) {"
  end

  test "converts empty? method" do
    erb = "<% if items.empty? %><p>Empty</p><% end %>"
    js = convert(erb)

    assert_includes js, "if (items.length === 0) {"
  end

  test "converts include? to includes" do
    erb = "<% if tags.include?('ruby') %><p>Ruby</p><% end %>"
    js = convert(erb)

    assert_includes js, "if (tags.includes('ruby')) {"
  end

  test "converts first and last" do
    erb = "<%= items.first %> and <%= items.last %>"
    js = convert(erb)

    assert_includes js, "html += (items[0] ?? '');"
    assert_includes js, "html += (items[items.length - 1] ?? '');"
  end

  test "converts %w array syntax" do
    erb = "<% if %w(Open Closed).include?(category) %><p>Match</p><% end %>"
    js = convert(erb)

    assert_includes js, "if (['Open', 'Closed'].includes(category)) {"
  end

  test "converts and/or/not boolean operators" do
    erb = "<% if active and not hidden or special %><p>Show</p><% end %>"
    js = convert(erb)

    assert_includes js, "if (active && !hidden || special) {"
  end

  test "converts dom_id helper" do
    erb = '<div id="<%= dom_id(subject) %>">Content</div>'
    js = convert(erb)

    assert_includes js, "html += (domId(subject) ?? '');"
  end

  test "escapes backticks in HTML" do
    erb = "<code>`console.log('hi')`</code>"
    js = convert(erb)

    assert_includes js, "html += `<code>\\`console.log('hi')\\`</code>`;"
  end

  test "escapes dollar-brace in HTML" do
    erb = "<p>Template: ${variable}</p>"
    js = convert(erb)

    assert_includes js, "html += `<p>Template: \\${variable}</p>`;"
  end

  test "function returns html" do
    erb = "<div>Test</div>"
    js = convert(erb)

    assert_includes js, "export function render(data) {"
    assert_includes js, "let html = '';"
    assert_includes js, "return html;"
    assert_includes js, "}"
  end

  test "handles nested conditionals" do
    erb = <<~ERB
      <% if user %>
      <% if user.admin? %>
      <p>Admin</p>
      <% end %>
      <% end %>
    ERB
    js = convert(erb)

    assert_includes js, "if (user) {"
    assert_includes js, "if (user.admin?) {"
    # Should have matching braces (function has both { and })
    assert_equal js.scan(/\{/).count, js.scan(/\}/).count
  end

  test "handles instance variables with underscores" do
    erb = "<%= @track_ages %>"
    js = convert(erb)

    assert_includes js, "html += (data.track_ages ?? '');"
  end

  test "converts multiple instance variables in one expression" do
    erb = '<div class="<%= @style %>" data-id="<%= @heat_id %>"></div>'
    js = convert(erb)

    assert_includes js, "html += (data.style ?? '');"
    assert_includes js, "html += (data.heat_id ?? '');"
  end

  test "handles complex each with instance variable" do
    erb = <<~ERB
      <% @subjects.each do |subject| %>
      <p><%= subject.name %></p>
      <% end %>
    ERB
    js = convert(erb)

    assert_includes js, "for (const subject of data.subjects) {"
  end

  test "handles comparison operators in conditionals" do
    erb = <<~ERB
      <% if count > 10 %>
      <p>Many</p>
      <% elsif count == 0 %>
      <p>None</p>
      <% end %>
    ERB
    js = convert(erb)

    assert_includes js, "if (count > 10) {"
    assert_includes js, "} else if (count == 0) {"
  end

  test "converts ternary operator" do
    erb = '<span class="<%= active ? "green" : "red" %>">Status</span>'
    js = convert(erb)

    assert_includes js, 'html += (active ? "green" : "red" ?? \'\');'
  end

  test "handles mixed HTML and ERB on same line" do
    erb = '<tr><td><%= name %></td><td><%= score %></td></tr>'
    js = convert(erb)

    assert_includes js, "html += `<tr><td>`;"
    assert_includes js, "html += (name ?? '');"
    assert_includes js, "html += `</td><td>`;"
    assert_includes js, "html += (score ?? '');"
    assert_includes js, "html += `</td></tr>`;"
  end

  test "converts method calls with parentheses" do
    erb = '<%= subject.method(arg) %>'
    js = convert(erb)

    assert_includes js, "html += (subject.method(arg) ?? '');"
  end

  test "converts safe navigation on array access" do
    erb = '<% items[key]&.each do |item| %><p><%= item %></p><% end %>'
    js = convert(erb)

    # Converter uses defensive fallback pattern instead of optional chaining
    assert_includes js, "for (const item of (items[key] || [])) {"
  end

  test "handles dom_id with argument" do
    erb = '<div id="<%= dom_id(subject) %>">Content</div>'
    js = convert(erb)

    assert_includes js, "html += (domId(subject) ?? '');"
  end

  test "handles gsub with string arguments" do
    erb = "<%= text.gsub(' ', '-') %>"
    js = convert(erb)

    assert_includes js, "html += (text.replace(' ', '-') ?? '');"
  end

  test "converts method call without parentheses in output" do
    erb = '<div id="<%= dom_id subject %>">Content</div>'
    js = convert(erb)

    assert_includes js, "html += (domId(subject) ?? '');"
  end

  test "converts chained method calls with arguments" do
    erb = "<%= category.gsub(' ', '').upcase %>"
    js = convert(erb)

    assert_includes js, "html += (category.replace(' ', '').upcase ?? '');"
  end

  test "converts complex blank check in conditional" do
    erb = "<% if active and not value.blank? %><p>Show</p><% end %>"
    js = convert(erb)

    assert_includes js, "if (active && !(value == null || value.length === 0)) {"
  end

  test "handles includes with method call without parens" do
    erb = "<% if %w(Open Closed).include? category %><p>Match</p><% end %>"
    js = convert(erb)

    assert_includes js, "if (['Open', 'Closed'].includes(category)) {"
  end

  test "converts each_with_index loop" do
    erb = <<~ERB
      <% items.each_with_index do |item, index| %>
      <p><%= index %>: <%= item %></p>
      <% end %>
    ERB
    js = convert(erb)

    assert_includes js, "for (const [index, item] of items.entries()) {"
  end

  test "converts string interpolation" do
    erb = '<%= "Hello #{name}, age #{age}" %>'
    js = convert(erb)

    assert_includes js, "html += (`Hello ${name}, age ${age}` ?? '');"
  end

  test "converts string interpolation with method calls" do
    erb = '<%= "Category: #{subject.entry.level.initials}" %>'
    js = convert(erb)

    assert_includes js, "html += (`Category: ${subject.entry.level.initials}` ?? '');"
  end

  test "converts nil to null" do
    erb = "<% value = nil %><%= value %>"
    js = convert(erb)

    assert_includes js, "const value = null;"
  end

  test "handles negation with empty?" do
    erb = "<% if !items.empty? %><p>Has items</p><% end %>"
    js = convert(erb)

    assert_includes js, "if (!(items.length === 0)) {"
  end
end
