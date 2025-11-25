# Proposal: Migrate ERB-to-JS Converter to Herb Parser

## Current Problem

The regex-based converter (`lib/erb_to_js_converter.rb`) is hitting fundamental limitations:

### Failing Patterns
1. **Method chaining**: `@results.keys.first.start_with?('{')`
2. **Context-dependent syntax**: Empty object `{}` valid in some contexts, not others
3. **Nested constructs**: `@results.keys.first.start_with?('{') ? JSON.parse(@results.keys.first) : {}`
4. **Ruby-specific idioms**: Ternary expressions, symbol access, method calls with blocks

### The Classic Transpiler Trap

Every transpiler project follows this pattern:
1. "I'll just use regex/gsub - it's simple!"
2. Add special cases for edge cases
3. Realize regex can't handle nesting/context
4. Need proper tokenizer/parser
5. Rewrite with AST

**We're at step 4.**

## Why Herb?

**Herb** (https://github.com/marcoroth/herb) is a modern, HTML-aware ERB parser that:

✅ **Written in C** - Fast, portable, precompiled gem
✅ **Generates AST** - Proper syntax tree for transformation
✅ **HTML-aware** - Understands ERB in HTML context
✅ **Battle-tested** - Powers VS Code extension, formatters, linters
✅ **Active development** - Introduced at RubyKaigi 2025
✅ **Well-documented** - Has playground, LSP, formatter built on it

## Proposed Architecture

### Phase 1: Research & Prototype
```ruby
require 'herb'

# Parse ERB template
ast = Herb.parse_file('app/views/scores/_table_heat.html.erb')

# Traverse AST and convert to JavaScript
converter = HerbToJsConverter.new
js_code = converter.convert(ast)
```

### Phase 2: AST Visitor Pattern
```ruby
class HerbToJsConverter
  def visit_erb_output_node(node)
    # <%= expr %> -> html += (#{convert_ruby_expr(node.code)} ?? '');
  end

  def visit_erb_code_node(node)
    # <% if %>, <% @items.each do %>, etc.
  end

  def visit_html_node(node)
    # Plain HTML -> html += `...`;
  end

  def convert_ruby_expr(ruby_code)
    # Use Prism parser here for Ruby AST
    # Convert Ruby AST to JavaScript AST
  end
end
```

### Phase 3: Ruby-to-JS with Prism
```ruby
require 'prism'  # Official Ruby parser (ships with Ruby 3.3+)

class RubyToJsConverter
  def convert(ruby_code)
    ast = Prism.parse(ruby_code)
    visit(ast.value)
  end

  def visit_call_node(node)
    # @results.keys.first -> data.results.keys[0]
  end

  def visit_symbol_node(node)
    # :style -> 'style'
  end

  # ... proper node visitors for all Ruby constructs
end
```

## Benefits

### 1. Correctness
- **AST-based**: Handles nesting, precedence, context correctly
- **No regex ambiguity**: Parser understands Ruby grammar
- **Proper scoping**: Track variables, method calls, context

### 2. Maintainability
- **Visitor pattern**: Clean separation of concerns
- **Testable**: Test each node type independently
- **Extensible**: Add new Ruby constructs by adding visitors

### 3. Error Handling
- **Syntax errors**: Parser catches malformed ERB
- **Unsupported constructs**: Clear error messages
- **Source locations**: Line/column info for debugging

### 4. Future-Proof
- **Ruby evolution**: Prism is official Ruby parser
- **ERB evolution**: Herb tracks ERB spec
- **New features**: Add support incrementally

## Migration Path

### Step 1: Install Herb
```ruby
# Gemfile
gem 'herb'
```

### Step 2: Experiment with Herb API
Create `lib/herb_explorer.rb` to:
- Parse one of our templates
- Inspect AST structure
- Understand node types

### Step 3: Prototype Converter
Create `lib/herb_to_js_converter.rb`:
- Start with simple cases (HTML only)
- Add ERB output (`<%= %>`)
- Add ERB code (`<% %>`)
- Handle loops, conditionals

### Step 4: Add Prism for Ruby
Integrate `Prism` parser for Ruby expressions:
- Parse Ruby code within ERB tags
- Convert Ruby AST to JavaScript
- Handle method chains, operators, literals

### Step 5: Parallel Implementation
- Keep old converter (`erb_to_js_converter.rb`)
- Add new converter (`herb_to_js_converter.rb`)
- Compare outputs in tests
- Switch when feature-complete

### Step 6: Validation
- Run existing tests
- Compare generated JS (old vs new)
- Verify syntax validation passes
- Test in browser

## Risks & Mitigations

### Risk: Herb API may not expose needed details
**Mitigation**: Use Herb CLI to explore AST, check GitHub issues, contact maintainer

### Risk: Prism complexity
**Mitigation**: Start with limited Ruby subset, expand incrementally

### Risk: Development time
**Mitigation**:
- Keep regex version working
- Migrate incrementally
- Value: Long-term correctness worth initial investment

## Success Criteria

✅ All 4 templates generate valid JavaScript
✅ JS syntax validation test passes
✅ Output matches current converter for simple cases
✅ Handles complex cases current converter fails
✅ Maintainable code with clear structure
✅ Extensible for future ERB constructs

## Next Steps

1. **Install Herb**: Add to Gemfile, bundle install
2. **Explore API**: Create script to parse template and inspect AST
3. **Document AST**: Write down node types for our templates
4. **Prototype**: Implement visitor for one simple template
5. **Evaluate**: Decide if Herb provides what we need
6. **Commit or pivot**: Either proceed with Herb or explore alternatives

## Alternatives Considered

### 1. Fix current regex approach
**Pros**: No dependencies
**Cons**: Already at limits, will hit more edge cases

### 2. Write custom ERB parser
**Pros**: Full control
**Cons**: Months of work, reinventing wheel, maintenance burden

### 3. Use existing Ruby-to-JS transpiler
**Pros**: Someone else's problem
**Cons**: Opal is for full Ruby apps, not template snippets

### 4. Use Herb (RECOMMENDED)
**Pros**: Purpose-built for ERB, maintained, battle-tested
**Cons**: Learning curve, dependency

## Conclusion

The regex approach has served us well for prototyping, but we've hit its fundamental limits. **Herb provides the proper foundation** for a robust, maintainable ERB-to-JavaScript converter.

The syntax validation test you suggested perfectly illustrates the problem - we need a real parser to generate correct JavaScript reliably.

**Recommendation**: Invest in migrating to Herb. The upfront cost is worth the long-term correctness and maintainability.
