# ERB → Prism Direct Approach

## Key Insight

**ERB compiles to Ruby, and that Ruby can be parsed by Prism!**

This eliminates the "incomplete expression" problem entirely.

## How It Works

### Step 1: ERB Compilation

```ruby
erb = ERB.new(template)
ruby_code = erb.src
```

Produces predictable Ruby code:

```ruby
_erbout = +''
_erbout.<< "static HTML".freeze
if @condition
  _erbout.<<(( @expression ).to_s)
end
@collection.each do |item|
  _erbout.<<(( item.property ).to_s)
end
_erbout
```

### Step 2: Prism Parsing

```ruby
result = Prism.parse(ruby_code)
# ✅ Always succeeds - it's complete, valid Ruby
```

### Step 3: AST Walking

The compiled Ruby has a **predictable structure**:

1. **`_erbout = +''`** → Initialize output buffer (skip in JS)
2. **`_erbout.<< "text".freeze`** → Static HTML → `html += \`text\``
3. **`_erbout.<<(( expr ).to_s)`** → Dynamic output → `html += (expr ?? '')`
4. **`if`/`unless`/`elsif`/`else`** → Direct JavaScript equivalents
5. **`.each do |x|`** → `for (const x of ...)`
6. **`_erbout`** → Final return (skip in JS)

## Benefits Over Other Approaches

### vs. Regex-only Approach
- ✅ **No regex brittleness** - proper AST parsing
- ✅ **No incomplete expressions** - ERB produces complete Ruby
- ✅ **Proper nesting** - AST knows structure
- ✅ **Better error messages** - Prism shows exact issues

### vs. Herb + Regex Approach
- ✅ **Simpler** - one parser (Prism) instead of two (Herb + regex)
- ✅ **More robust** - ERB handles all edge cases
- ✅ **Complete expressions** - no need to regex-parse blocks
- ✅ **Ruby-native** - uses Ruby's own compilation

### vs. Herb + Prism Hybrid
- ✅ **No Herb dependency** - Prism ships with Ruby
- ✅ **Single transformation** - ERB → JS (not ERB → Herb AST → Prism AST → JS)
- ✅ **Leverages ERB's work** - ERB already solved template → Ruby
- ✅ **Future-proof** - follows ERB's evolution

## Predictable Patterns to Convert

### Static HTML

**Ruby**: `_erbout.<< "text".freeze`
**Prism**: `CallNode(<<)` with `StringNode` argument
**JavaScript**: `html += \`text\``

### Dynamic Output

**Ruby**: `_erbout.<<(( expr ).to_s)`
**Prism**: `CallNode(<<)` with nested `CallNode(to_s)` containing `ParenthesesNode`
**JavaScript**: `html += (expr ?? '')`

### If Statements

**Ruby**: `if condition ... end`
**Prism**: `IfNode` with predicate and statements
**JavaScript**: `if (condition) { ... }`

### Loops

**Ruby**: `@items.each do |x| ... end`
**Prism**: `CallNode(each)` with `BlockNode`
**JavaScript**: `for (const x of items) { ... }`

### Variable Assignments

**Ruby**: `var = value`
**Prism**: `LocalVariableWriteNode`
**JavaScript**: `const var = value`

## Challenges & Solutions

### Challenge 1: `.freeze` in Strings

**Problem**: `_erbout.<< "text".freeze` includes `.freeze`
**Solution**: The `StringNode` has `unescaped` property with clean text

### Challenge 2: Extracting Expression from `(( expr ).to_s)`

**Problem**: Nested structure: `CallNode[to_s]` → `ParenthesesNode` → `StatementsNode` → actual expression
**Solution**:
```ruby
if arg.name == :to_s && arg.receiver.is_a?(Prism::ParenthesesNode)
  inner_expr = arg.receiver.body.body[0]  # StatementsNode → first statement
  js_expr = convert(inner_expr)
end
```

### Challenge 3: Loop Variables

**Problem**: `.each do |item|` - need to extract block parameter name
**Solution**: `BlockNode` has `parameters` property with parameter names

### Challenge 4: Rails Helpers

**Problem**: ERB compiles Rails helpers as-is: `dom_id(@object)`
**Solution**: Same as before - detect specific method names and convert:
- `*_path` → template strings
- `dom_id` → `domId` function

### Challenge 5: Variable Scope

**Problem**: `subject` vs. `@subject` - which needs `data.` prefix?
**Solution**: Track scope:
- **Instance variables** (`@var`) → always `data.var`
- **Local variables** (from `each` blocks, assignments) → no prefix
- **Bare method calls** (`subject`) → heuristic: if it's a known template var, use `data.subject`

## Implementation Strategy

### Phase 1: Core Converter
1. Compile ERB → Ruby
2. Parse Ruby with Prism
3. Walk AST, converting patterns:
   - `_erbout.<<` → HTML output
   - `if`/`unless` → JavaScript conditionals
   - `.each` → for loops
   - Variables → proper scoping

### Phase 2: Expression Conversion
1. Reuse existing `ruby_to_js` logic for expressions
2. Add Prism-based conversion for complex cases
3. Handle Rails helpers

### Phase 3: Edge Cases
1. String interpolation
2. Ternary operators
3. Complex method chains
4. Safe navigation

## Proof of Concept Results

Created `script/erb_prism_converter_prototype.rb`:

**Input ERB**:
```erb
<% if @show_header %>
  <h1><%= @title %></h1>
<% end %>
```

**Output JavaScript**:
```javascript
if (data.show_header) {
  html += `<h1>`;
  html += (data.title ?? '');
  html += `</h1>`;
}
```

✅ **Core concept validated!**

## Next Steps

1. **Handle `.each` loops** - convert `BlockNode` to JavaScript for loops
2. **Clean up string handling** - remove `.freeze`, fix escaping
3. **Add variable scope tracking** - distinguish template vars from locals
4. **Handle all CallNode patterns** - method chains, safe nav, etc.
5. **Run against existing tests** - verify against 42 current test cases
6. **Replace current converter** - migrate from regex to ERB→Prism approach

## Recommendation

**Use the ERB → Prism approach!**

This is simpler, more robust, and leverages Ruby's built-in ERB compilation. It eliminates the "incomplete expression" problem and provides a single, clean transformation path.

Herb is interesting but unnecessary - ERB already does the template → Ruby transformation, and Prism can parse the result directly.
