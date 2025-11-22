# Herb Exploration Summary

## What Was Explored

Explored Herb v0.8.2 (HTML-aware ERB parser) to understand its capabilities and suitability for replacing the regex-based ERB-to-JavaScript converter.

## Key Findings

### ✅ Herb Successfully Handles All Our Patterns

Tested Herb with complex Ruby patterns from our actual templates:

1. **Safe navigation with `.each`**: `@results[score]&.each do |result|` ✅
2. **params hash access**: `params[:style]` ✅
3. **Complex ternaries**: `@results.keys.first.start_with?('{') ? JSON.parse(...) : {}` ✅
4. **Nested method chains**: `subject.entry.lead.back.number` ✅
5. **Rails path helpers**: `update_rank_path(judge: @judge)` ✅
6. **Boolean logic with `.blank?`**: `!subject.category.include? 'Newcomer' and !subject.entry.lead.back.blank?` ✅
7. **Array word syntax**: `%w(Solo Jack\ and\ Jill)` ✅

**Result**: Herb parses all these patterns successfully and extracts the Ruby code exactly as written.

### 🔍 What Herb Provides

1. **Accurate ERB Parsing**: Herb correctly identifies all ERB tag types:
   - `ERBIfNode`, `ERBUnlessNode`, `ERBElsifNode`, `ERBElseNode`
   - `ERBBlockNode` (for `.each` loops)
   - `ERBContentNode` (for output `<%= %>` and code blocks `<% %>`)
   - `ERBEndNode` (structural `<% end %>` markers)

2. **Clean Ruby Code Extraction**:
   - Each ERB node has a `@content` token with the Ruby code
   - Code is preserved exactly (including whitespace)
   - No parsing or interpretation of the Ruby code itself

3. **HTML Structure Preservation**:
   - `HTMLElementNode`, `HTMLTextNode`, `DocumentNode`
   - Maintains proper nesting and structure
   - Handles both HTML and ERB intermixed

### 🎯 What Herb Does NOT Provide

**Herb only parses ERB/HTML structure - it does NOT parse Ruby code.**

The `@content` tokens contain raw Ruby strings like:
- `"if @show_header"`
- `"@items.each do |item|"`
- `"subject.entry.lead.back.number"`

To convert these Ruby expressions to JavaScript, we still need:
1. **Ruby expression parsing** (Prism or regex)
2. **Ruby-to-JavaScript conversion logic** (can reuse from existing converter)

### 📊 AST Structure

Example for `<% if @show_header %><h1><%= @title %></h1><% end %>`:

```
DocumentNode
└── ERBIfNode
    ├── @content: Token("if @show_header")
    ├── @statements: [
    │   ├── HTMLElementNode (h1)
    │   │   └── ERBContentNode
    │   │       └── @content: Token("@title")
    │   └── ERBEndNode
    ]
```

## Architecture Decision

### Recommended Approach: **Hybrid (Herb + Existing Ruby-to-JS)**

**Why:**
1. **Herb solves the template parsing problem** - cleanly separates HTML from ERB
2. **Existing `ruby_to_js` method can be reused** - we've already solved most Ruby-to-JS patterns
3. **Incremental migration path** - can switch template parsing to Herb while keeping Ruby conversion logic

**Implementation:**
```ruby
class HerbErbToJsConverter
  def convert(template)
    result = Herb.parse(template)
    ast = result.value

    lines = []
    lines << "export function render(data) {"
    lines << "  let html = '';"
    lines << ""

    process_node(ast, lines, indent_level: 2)

    lines << ""
    lines << "  return html;"
    lines << "}"

    lines.join("\n")
  end

  def process_node(node, lines, indent_level:)
    case node
    when Herb::AST::ERBIfNode
      content = node.instance_variable_get(:@content).value
      condition = content.sub(/^if\s+/, '').strip
      js_condition = ruby_to_js(condition)  # Reuse existing method!
      lines << indent(indent_level, "if (#{js_condition}) {")
      process_statements(node, lines, indent_level + 1)
      lines << indent(indent_level, "}")

    when Herb::AST::ERBContentNode
      content = node.instance_variable_get(:@content).value.strip
      js_expr = ruby_to_js(content)  # Reuse existing method!
      lines << indent(indent_level, "html += (#{js_expr} ?? '');")

    when Herb::AST::HTMLTextNode
      text = node.instance_variable_get(:@content)
      # Escape for template literal
      lines << indent(indent_level, "html += `#{escape_for_template(text)}`;")

    # ... handle other node types
    end
  end

  def ruby_to_js(expr)
    # Reuse existing conversion logic from lib/erb_to_js_converter.rb!
    # This already handles @vars, params[:key], .blank?, etc.
  end
end
```

## Benefits of Herb Approach

1. **✅ Eliminates regex brittleness** for template structure parsing
2. **✅ Proper nesting handling** - AST knows parent/child relationships
3. **✅ Better error messages** - Herb reports location of parse errors
4. **✅ Reuses existing Ruby-to-JS logic** - no need to rewrite proven code
5. **✅ Future-proof** - Herb maintained by Rails community (Marco Roth)

## Files Created During Exploration

1. `script/explore_herb.rb` - Basic Herb API exploration
2. `script/explore_herb_detailed.rb` - Deep dive into node properties
3. `script/test_herb_complex.rb` - Testing with actual template patterns
4. `plans/HERB_AST_STRUCTURE.md` - Complete AST documentation

## Next Steps

1. **Prototype the hybrid converter** (Herb for structure + existing Ruby-to-JS)
2. **Run existing test suite** against hybrid converter
3. **Compare generated JavaScript** - should be identical or better
4. **Benchmark performance** - Herb (C extension) may be faster than regex
5. **Gradual migration** - can run both converters in parallel initially

## Conclusion

**Herb is the right tool for this job.** It solves the fundamental problem (template structure parsing) while allowing us to reuse our existing Ruby-to-JavaScript conversion logic. The migration path is clear and low-risk.
