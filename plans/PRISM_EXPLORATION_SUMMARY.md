# Prism Exploration Summary

## Overview

Explored **Prism** (Ruby's official parser, ships with Ruby 3.3+) for parsing Ruby expressions extracted from ERB templates.

## Key Findings

### ✅ Prism Successfully Parses Ruby Expressions

Tested with complex patterns from our templates:

1. **Instance variables**: `@title` → `InstanceVariableReadNode`
2. **Method chains**: `subject.entry.lead.back.number` → Nested `CallNode`s
3. **Safe navigation**: `@results[score]&.each` → `CallNode` with `safe_navigation` flag
4. **Hash access**: `params[:style]` → `CallNode` with `[]` method + `SymbolNode` arg
5. **Complex ternaries**: Parses successfully with `IfNode`
6. **Boolean logic**: `AndNode`, `OrNode`, `NotNode`
7. **Arrays**: `%w(Solo Jack)` → `ArrayNode` with `StringNode` elements
8. **Assignments**: `var = value` → `LocalVariableWriteNode`

### 🎯 What Prism Provides

**Complete Ruby AST** with detailed node types:
- `InstanceVariableReadNode` - `@variable`
- `CallNode` - all method calls, with flags for `safe_navigation`, `variable_call`, etc.
- `LocalVariableReadNode` / `LocalVariableWriteNode`
- `StringNode`, `InterpolatedStringNode`, `SymbolNode`
- `ArrayNode`, `HashNode`
- `IfNode`, `AndNode`, `OrNode`, `NotNode`
- `IntegerNode`, `TrueNode`, `FalseNode`, `NilNode`

**Flags for call nodes** (bitmask):
- `SAFE_NAVIGATION` - `&.` operator
- `VARIABLE_CALL` - bare identifier (no parens)
- `IGNORE_VISIBILITY` - accessing private methods

## Prototype Results

Created `script/prism_to_js_prototype.rb` with AST-based conversion.

### ✅ Successful Conversions (5/8 passing)

```ruby
"@title"                           → "data.title" ✅
"@results[score]"                  → "data.results[score]" ✅
"params[:style]"                   → "params['style']" ✅
"@results.keys.first"              → "Object.keys(data.results)[0]" ✅
"options = @results.keys.first"    → "const options = Object.keys(data.results)[0]" ✅
```

### ⚠️ Issues Found

#### 1. Context-Dependent Variables

**Problem**: Bare identifiers like `subject` could be:
- Template data: `subject` → `data.subject`
- Local JavaScript variables: `score` → `score` (no prefix)

**Example**:
```ruby
# In template: subject comes from data
subject.entry.lead.back.number → data.subject.entry.lead.back.number

# But in loop: score is local
@results[score] → data.results[score]  # score stays as-is
```

**Prism can't distinguish** - it just sees a `CallNode` with `variable_call` flag.

**Solution**: Need to track which variables are from template `data` vs. local scope:
- Instance variables (`@var`) → always `data.var`
- Known template variables → `data.var`
- Loop variables, local assignments → no prefix

#### 2. Incomplete Block Expressions

**Problem**: Prism can't parse incomplete blocks:
```ruby
"@items.each do |item|"  # Missing 'end'
→ Parse error: "expected a block beginning with `do` to end with `end`"
```

**Solution**: For block patterns, use regex to extract:
- Collection: `@items`
- Block vars: `item`
- Then convert collection using Prism

#### 3. Rails-Specific Helpers

**Problem**: Prism doesn't know about Rails helpers:
```ruby
"update_rank_path(judge: @judge)"
→ Parses as CallNode with keyword argument
```

**Solution**: Post-process specific method names:
- Detect `*_path` / `*_url` methods
- Convert keyword arguments to path template strings

## Recommended Architecture

### Three-Layer Approach: **Herb + Prism + Custom Logic**

```ruby
class HerbPrismErbToJsConverter
  def convert(template)
    # Layer 1: Parse ERB structure with Herb
    herb_result = Herb.parse(template)
    ast = herb_result.value

    # Layer 2: Walk Herb AST
    process_node(ast)
  end

  def process_node(node)
    case node
    when Herb::AST::ERBContentNode
      ruby_code = node.instance_variable_get(:@content).value.strip

      # Layer 3: Parse Ruby expression with Prism
      prism_result = Prism.parse(ruby_code)
      if prism_result.success?
        js_expr = convert_prism_ast(prism_result.value)
        add_output(js_expr)
      else
        # Fallback to regex for incomplete expressions
        js_expr = ruby_to_js_regex(ruby_code)
        add_output(js_expr)
      end

    when Herb::AST::ERBBlockNode
      ruby_code = node.instance_variable_get(:@content).value.strip

      # Special handling for blocks (use regex to extract pattern)
      if ruby_code =~ /(.+?)\.each\s+do\s+\|(.+?)\|/
        collection_expr = $1
        block_vars = $2.split(',').map(&:strip)

        # Convert collection with Prism
        prism_result = Prism.parse(collection_expr)
        js_collection = convert_prism_ast(prism_result.value)

        # Generate JavaScript loop
        add_line("for (const #{block_vars[0]} of #{js_collection}) {")
        # ... process block body
      end
    end
  end

  def convert_prism_ast(program_node)
    stmt = program_node.statements.body[0]
    convert_prism_node(stmt)
  end

  def convert_prism_node(node)
    case node
    when Prism::InstanceVariableReadNode
      "data.#{node.name.to_s.delete_prefix('@')}"

    when Prism::CallNode
      # Check flags, convert method names, handle safe navigation
      # (reuse logic from prototype)

    # ... other node types
    end
  end
end
```

## Benefits of Prism

1. **✅ Accurate Ruby parsing** - no regex guessing for expressions
2. **✅ Proper AST structure** - method chains, operator precedence
3. **✅ Future-proof** - official Ruby parser, will support new syntax
4. **✅ Rich metadata** - flags, locations, node types
5. **✅ Battle-tested** - used by Ruby itself

## Limitations

1. **❌ Needs complete expressions** - can't parse `do |x|` without `end`
2. **❌ No Rails awareness** - doesn't know about `*_path`, `render`, etc.
3. **❌ No template context** - can't distinguish `data.x` vs. local `x`

## Hybrid Strategy

**Use Prism where it excels, regex where necessary:**

- **Prism for**: Output expressions (`<%= expr %>`), conditions, assignments
- **Regex for**: Block patterns (`each do |x|`), Rails helpers, incomplete syntax
- **Custom logic for**: Variable scope tracking, template data vs. locals

## Files Created

1. `script/explore_prism.rb` - Initial Prism API exploration
2. `script/prism_to_js_prototype.rb` - Working AST-based converter (5/8 tests passing)

## Next Steps

1. **Integrate Prism into converter** - use for output expressions and conditions
2. **Add variable scope tracking** - distinguish template data from locals
3. **Keep regex for blocks** - handle `each do |x|` patterns
4. **Add Rails helper detection** - special cases for `*_path`, etc.
5. **Run full test suite** - verify against all 42 existing tests

## Conclusion

**Prism is valuable but not a silver bullet.** It provides accurate Ruby parsing for complete expressions, but we still need:
- Regex for incomplete/block syntax
- Custom logic for Rails helpers and variable scoping
- Herb for ERB structure

The three-layer approach (Herb + Prism + Custom) provides the best of all worlds.
