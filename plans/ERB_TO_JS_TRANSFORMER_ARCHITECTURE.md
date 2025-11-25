# ERB to JavaScript Transformer Architecture

## Status: Future Consideration

This plan documents a potential refactoring of `ErbPrismConverter` into a modular,
reusable architecture. Currently the converter is a single 841-line file that mixes
ERB-specific, Rails-specific, and application-specific concerns. This works but
makes it hard to reuse or configure for different applications.

## Current Architecture

```
ERB template
    ↓ (Rails ERB handler)
Ruby source code
    ↓ (Prism.parse)
Ruby AST
    ↓ (ErbPrismConverter - monolithic)
JavaScript source code
```

All transformation logic is in one `convert_call` method with a large case statement.
Application-specific rules (like `subject_category`) are mixed in with Ruby core
and Rails transformations.

## Proposed Architecture

```
ERB template
    ↓ (Rails ERB handler)
Ruby source code
    ↓ (Prism.parse)
Ruby AST
    ↓ (ERB transformer) - strips @output_buffer patterns, extracts HTML
    ↓ (Rails transformer) - dom_id → domId, link_to → <a> tags
    ↓ (App transformer) - configured via options/YAML
Ruby AST (normalized)
    ↓ (Ruby→JS converter) - generic, no domain knowledge
JavaScript source code
```

### Components

#### 1. Base Ruby→JS Converter
Pure Ruby-to-JavaScript conversion with no domain knowledge:
- Operators: `==`, `+`, `-`, etc.
- Core methods: `.max`, `.first`, `.include?`, `.blank?`
- Control flow: `if`, `unless`, `each`
- Literals: strings, arrays, hashes, ranges

#### 2. ERB Transformer (AST → AST)
Normalizes ERB compilation artifacts:
- Removes `@output_buffer.safe_append=` patterns
- Extracts string literals as HTML output
- Handles `_erbout` variable

#### 3. Rails Transformer (AST → AST)
Converts Rails view helpers:
- `dom_id` → `domId()`
- `link_to` → `<a>` tag generation
- `image_tag` → `<img>` tag generation
- Path helpers → stub or configurable URLs

#### 4. Application Transformer (AST → AST, Configurable)
Handles app-specific patterns via configuration:

```yaml
# config/erb_to_js.yml
precomputed_properties:
  # method_name: strip arguments, treat as property access
  - subject_category
  - subject_lvlcat

custom_helpers:
  # helper_name: replacement strategy
  my_helper: stub  # returns ''
  other_helper: passthrough  # keeps as function call
```

### API Design

```ruby
# Default usage (reads config/erb_to_js.yml)
converter = ErbToJs::Converter.new(erb_template)
js_code = converter.convert

# Programmatic configuration
converter = ErbToJs::Converter.new(erb_template,
  precomputed: [:subject_category, :custom_method],
  skip_rails: false
)

# Pipeline customization
converter = ErbToJs::Converter.new(erb_template)
converter.add_transformer(MyCustomTransformer.new)
js_code = converter.convert
```

### Transformer Interface

```ruby
module ErbToJs
  class Transformer
    # Transform a single AST node, return transformed node or nil to skip
    def transform(node)
      node  # default: pass through unchanged
    end

    # Called before traversal starts
    def before_convert(ast)
    end

    # Called after traversal completes
    def after_convert(js_lines)
      js_lines
    end
  end
end
```

## Implementation Considerations

### AST Mutability
Prism AST nodes are immutable. Options:
1. Create wrapper nodes that delegate to original
2. Build a mutable intermediate representation
3. Use a "rewrite rules" approach that pattern-matches and rebuilds

### Performance
Multiple AST traversals vs single pass. Likely negligible for template sizes,
but could optimize with a single traversal that applies all transformers.

### Testing Strategy
- Unit tests for each transformer in isolation
- Integration tests for full pipeline
- Snapshot tests comparing output JS for sample templates

## Migration Path

1. Extract ERB-specific logic to `ErbTransformer`
2. Extract Rails-specific logic to `RailsTransformer`
3. Move app-specific rules to config file + `AppTransformer`
4. Refactor core converter to be domain-agnostic
5. Add pipeline orchestration
6. Extract to gem if there's external interest

## Pros

- **Separation of concerns** - Each transformer has single responsibility
- **Testability** - Test transformers in isolation
- **Discoverability** - App config in one visible file
- **Reusability** - Core converter becomes general-purpose
- **Composability** - Pick which transformers to apply
- **Debugging** - Inspect AST between stages

## Cons

- **Complexity** - More moving parts, harder to follow full flow
- **Over-engineering risk** - Current monolith works fine for one app
- **AST manipulation complexity** - Building/modifying nodes is harder than strings
- **Learning curve** - Contributors need to understand pipeline

## Decision

Defer this refactoring until there's a concrete need:
- Another application wants to use the converter
- The monolithic converter becomes unwieldy to maintain
- Interest from others in a reusable ERB→JS gem

For now, application-specific rules are documented with comments in the
`convert_call` method of `ErbPrismConverter`.
