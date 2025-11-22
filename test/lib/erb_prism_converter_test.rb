require "test_helper"
require "erb_prism_converter"

class ErbPrismConverterTest < ActiveSupport::TestCase
  def convert(erb_template)
    converter = ErbPrismConverter.new(erb_template)
    converter.convert
  end

  test "converts simple instance variable output" do
    erb = "<div><%= @title %></div>"
    js = convert(erb)

    assert_match /html \+= `<div>`;/, js
    assert_match /html \+= \(data\.title\) \|\| '';/, js
    assert_match /html \+= `<\/div>`;/, js
  end

  test "converts if statement" do
    erb = <<~ERB
      <% if @show_header %>
        <h1>Title</h1>
      <% end %>
    ERB

    js = convert(erb)

    assert_match /if \(data\.show_header\)/, js
    assert_match /<h1>Title<\/h1>/, js
  end

  test "converts unless statement" do
    erb = <<~ERB
      <% unless @hide %>
        <div>Visible</div>
      <% end %>
    ERB

    js = convert(erb)

    assert_match /if \(!\(data\.hide\)\)/, js
  end

  test "converts each loop" do
    erb = <<~ERB
      <% @items.each do |item| %>
        <div><%= item.name %></div>
      <% end %>
    ERB

    js = convert(erb)

    assert_match /for \(const item of data\.items\)/, js
    assert_match /item\.name/, js
  end

  test "converts safe navigation with each" do
    erb = <<~ERB
      <% @results&.each do |result| %>
        <span><%= result %></span>
      <% end %>
    ERB

    js = convert(erb)

    assert_match /for \(const result of \(data\.results \|\| \[\]\)\)/, js
  end

  test "converts method calls" do
    erb = "<%= @items.length %>"
    js = convert(erb)

    assert_match /data\.items\.length/, js
  end

  test "converts blank? method" do
    erb = "<% if @name.blank? %><p>Empty</p><% end %>"
    js = convert(erb)

    assert_match /if \(data\.name == null \|\| data\.name\.length === 0\)/, js
  end

  test "converts array access" do
    erb = "<%= @items[0] %>"
    js = convert(erb)

    assert_match /data\.items\[0\]/, js
  end

  test "converts hash access with symbol" do
    erb = "<%= params[:style] %>"
    js = convert(erb)

    assert_match /data\.params\['style'\]/, js
  end

  test "tracks local variables from loops" do
    erb = <<~ERB
      <% @items.each do |item| %>
        <%= item %>
      <% end %>
    ERB

    js = convert(erb)

    # item should not have data. prefix (it's a loop variable)
    assert_match /html \+= \(item\) \|\| '';/, js
    # item should appear without data. prefix in output
    refute_match /html \+= \(data\.item\) \|\| '';/, js
  end

  test "converts variable assignment" do
    erb = <<~ERB
      <% name = @person.name %>
      <%= name %>
    ERB

    js = convert(erb)

    assert_match /const name = data\.person\.name;/, js
    assert_match /html \+= \(name\) \|\| '';/, js
  end

  test "converts string interpolation" do
    erb = '<div class="heat-<%= @number %>">Content</div>'
    js = convert(erb)

    # ERB compiles interpolation into separate output statements, not template literals
    assert_match /html \+= `<div class="heat-`;/, js
    assert_match /html \+= \(data\.number\) \|\| '';/, js
    assert_match /html \+= `">Content<\/div>`;/, js
  end

  test "converts elsif chain" do
    erb = <<~ERB
      <% if @status == 'new' %>
        <span>New</span>
      <% elsif @status == 'pending' %>
        <span>Pending</span>
      <% else %>
        <span>Other</span>
      <% end %>
    ERB

    js = convert(erb)

    assert_match /if \(data\.status == "new"\)/, js
    assert_match /} else if \(data\.status == "pending"\)/, js
    assert_match /} else {/, js
  end

  test "escapes dollar signs in template literals" do
    erb = '<div>${dollar}</div>'
    js = convert(erb)

    # Dollar signs should be escaped in template literals
    assert_match /\\\$\{dollar\}/, js
  end
end
