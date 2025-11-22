# Herb AST Structure Documentation

Based on exploration of Herb v0.8.2, this document describes the AST node types and their properties.

## Key Findings

### ERB Node Types and Properties

All ERB nodes have the Ruby code stored in `@content` (a `Herb::Token` object with a `.value` method):

1. **ERBIfNode** - Represents `<% if condition %>`
   - `@content`: Token containing the condition with "if " prefix (e.g., `" if @show_header "`)
   - `@tag_opening`: Token `"<%"`
   - `@tag_closing`: Token `"%>"`
   - `@statements`: Array of child nodes (body of the if block)
   - `@subsequent`: Reference to elsif/else nodes (if any)

2. **ERBUnlessNode** - Represents `<% unless condition %>`
   - `@content`: Token containing the condition with "unless " prefix (e.g., `" unless @style == 'emcee' "`)
   - `@tag_opening`: Token `"<%"`
   - `@tag_closing`: Token `"%>"`
   - `@statements`: Array of child nodes (body of the unless block)

3. **ERBElsifNode** - Represents `<% elsif condition %>`
   - `@content`: Token containing the condition with "elsif " prefix
   - `@tag_opening`: Token `"<%"`
   - `@tag_closing`: Token `"%>"`
   - `@statements`: Array of child nodes (body of the elsif block)

4. **ERBElseNode** - Represents `<% else %>`
   - `@content`: Token with `" else "` (just the keyword)
   - `@tag_opening`: Token `"<%"`
   - `@tag_closing`: Token `"%>"`
   - `@statements`: Array of child nodes (body of the else block)

5. **ERBBlockNode** - Represents `<% @items.each do |item| %>`
   - `@content`: Token containing the full block expression (e.g., `" @items.each do |item| "`)
   - `@tag_opening`: Token `"<%"`
   - `@tag_closing`: Token `"%>"`
   - `@statements`: Array of child nodes (body of the block)

6. **ERBContentNode** - Represents `<%= expression %>` (output tag)
   - `@content`: Token containing the Ruby expression (e.g., `" item.name "`)
   - `@tag_opening`: Token `"<%="`
   - `@tag_closing`: Token `"%>"`
   - `@analyzed_ruby`: nil (for Ruby analysis)
   - `@parsed`: true/false
   - `@valid`: true/false
   - NOTE: Also used for code blocks that are just assignments (e.g., `<% var = value %>`)

7. **ERBEndNode** - Represents `<% end %>`
   - `@content`: Token with `" end "`
   - `@tag_opening`: Token `"<%"`
   - `@tag_closing`: Token `"%>"`
   - These are structural markers that Herb includes in the AST

### HTML Node Types

1. **HTMLElementNode**
   - `@tag_name`: Token with tag name (e.g., `"div"`)
   - `@is_void`: Boolean (true for `<br/>`, `<img/>`, etc.)
   - `@source`: `"HTML"` or `"ERB"`
   - Children in `@children` or `@body`

2. **HTMLTextNode**
   - `@content`: Plain string (not a Token) with the text content
   - Used for whitespace, text between tags, etc.

3. **DocumentNode**
   - Root node
   - Children in `@children`

## Example AST for Simple Template

```erb
<div class="container">
  <% if @show_header %>
    <h1><%= @title %></h1>
  <% end %>
  <% @items.each do |item| %>
    <div class="item"><%= item.name %></div>
  <% end %>
</div>
```

Produces:

```
DocumentNode
└── HTMLElementNode (div.container)
    ├── HTMLTextNode (whitespace)
    ├── ERBIfNode
    │   └── @content: Token(" if @show_header ")
    │   └── [children contain the h1 element]
    ├── HTMLTextNode (whitespace)
    ├── ERBBlockNode
    │   └── @content: Token(" @items.each do |item| ")
    │   └── [body contains div.item with ERBContentNode]
    └── HTMLTextNode (whitespace)
```

## Key Insights for Converter

### Access Ruby Code

To get the Ruby code from ERB nodes:

```ruby
# Get the content token
content_token = node.instance_variable_get(:@content)
ruby_code = content_token.value.strip if content_token

case node
when Herb::AST::ERBIfNode
  # ruby_code = "if @show_header"
  # Strip the "if " prefix to get just the condition
  condition = ruby_code.sub(/^if\s+/, '')

when Herb::AST::ERBUnlessNode
  # ruby_code = "unless @style == 'emcee'"
  # Strip the "unless " prefix to get just the condition
  condition = ruby_code.sub(/^unless\s+/, '')

when Herb::AST::ERBElsifNode
  # ruby_code = "elsif @column_order == 1"
  # Strip the "elsif " prefix to get just the condition
  condition = ruby_code.sub(/^elsif\s+/, '')

when Herb::AST::ERBBlockNode
  # ruby_code = "@items.each do |item|"
  # Parse to extract collection, variables, etc.
  # This is where regex or Prism parsing comes in

when Herb::AST::ERBContentNode
  # ruby_code = "item.name" or "var = value"
  # If it contains '=' it's an assignment, otherwise it's output
  if ruby_code.include?('=') && !ruby_code.match?(/[=!<>]=/)
    # It's an assignment: var = value
  else
    # It's an output expression
  end
end
```

### Distinguish Output vs Code Blocks

- `ERBContentNode` (`<%= %>`) - outputs to HTML, needs wrapping in `html += ...`
- All other ERB nodes - control flow, don't output directly

### Handle Nested Structures

- Use visitor pattern to traverse AST
- Track indentation depth as you descend into blocks
- ERB nodes can contain HTML, which can contain more ERB nodes

## Next Steps

1. **Ruby Expression Parser**: Need to parse the Ruby code within `@content` tokens
   - Use Prism (Ruby's official parser) to convert Ruby expressions to JavaScript
   - Handle method calls, operators, string interpolation, etc.

2. **Visitor Implementation**: Create converter that walks the Herb AST
   - Convert HTML nodes to template literal strings
   - Convert ERB control flow to JavaScript control flow
   - Convert ERB output to string concatenation

3. **Integration with Existing Converter**:
   - Replace regex-based template parsing with Herb
   - Keep Ruby-to-JS conversion logic (possibly enhanced with Prism)
   - Maintain existing test suite
