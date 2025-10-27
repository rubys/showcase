---
name: render-page
description: Techniques for rendering Rails pages without starting a server using the internal routing system. Use when the user needs to test page rendering, debug views, verify page correctness, or analyze rendering performance without HTTP overhead.
---

# Rendering Pages Without Starting a Server

You can render any page in the application without starting a Rails server. This is useful for testing page rendering, debugging views, or verifying that pages work correctly.

## Basic Technique

Use Rails' internal routing system to render pages directly:

```ruby
env = {
  "PATH_INFO" => '/showcase/path/to/page',
  "REQUEST_METHOD" => "GET"
}

code, headers, response = Rails.application.routes.call(env)

if code == 200
  html = response.body.force_encoding('utf-8')
  puts html
else
  puts "Error: #{code}"
  puts response.inspect
end
```

## Using bin/run

The easiest way to test page rendering is with `bin/run`:

```bash
# Test rendering a specific page
bin/run db/2025-boston.sqlite3 -e "
env = {
  'PATH_INFO' => '/showcase/2025/boston/',
  'REQUEST_METHOD' => 'GET'
}
code, _, response = Rails.application.routes.call(env)
puts code == 200 ? '✓ Success' : '✗ Failed'
"

# Get the full HTML output
bin/run db/2025-boston.sqlite3 -e "
env = {
  'PATH_INFO' => '/showcase/heats',
  'REQUEST_METHOD' => 'GET'
}
code, _, response = Rails.application.routes.call(env)
puts response.body if code == 200
"
```

## In a Script File

Create a script to test multiple pages:

```ruby
# test_rendering.rb
pages = [
  '/showcase/',
  '/showcase/heats',
  '/showcase/people',
  '/showcase/studios'
]

pages.each do |path|
  env = {
    "PATH_INFO" => path,
    "REQUEST_METHOD" => "GET"
  }

  code, _headers, response = Rails.application.routes.call(env)

  if code == 200
    puts "✓ #{path} - #{response.body.length} bytes"
  else
    puts "✗ #{path} - Error #{code}"
  end
end
```

Run it with:

```bash
bin/run db/2025-boston.sqlite3 test_rendering.rb
```

## Testing Specific Features

### Check if a page renders without errors

```ruby
env = {
  "PATH_INFO" => '/showcase/heats',
  "REQUEST_METHOD" => "GET"
}

code, _headers, response = Rails.application.routes.call(env)

if code == 200
  puts "Page rendered successfully"
else
  puts "Error: #{code}"
  exit 1
end
```

### Verify specific content in the response

```ruby
env = {
  "PATH_INFO" => '/showcase/people',
  "REQUEST_METHOD" => "GET"
}

code, _headers, response = Rails.application.routes.call(env)

if code == 200
  html = response.body.force_encoding('utf-8')
  if html.include?("Students")
    puts "✓ Students section found"
  else
    puts "✗ Students section missing"
  end
end
```

## Use Cases

1. **Testing**: Verify pages render without starting a server
2. **Debugging**: Inspect rendered HTML directly
3. **Performance Analysis**: Measure rendering time without HTTP overhead
4. **Validation**: Check that all expected pages render successfully after changes

## Reference

See `lib/tasks/prerender.rake` for a complete example of how this technique is used in production.
