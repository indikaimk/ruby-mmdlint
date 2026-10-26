# Mmdlint

[![Gem Version](https://badge.fury.io/rb/mmdlint.svg)](https://badge.fury.io/rb/mmdlint)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Ruby wrapper for Node.js [`@sysid/mmdlint`](https://github.com/sysid/mmdlint).

**Mmdlint** validates [Mermaid](https://mermaid.js.org/) diagram syntax inside standalone diagram strings or Markdown documents — **headless, in-process, and without launching a browser or Chromium renderer**.

It is purpose-built for Rails apps that generate diagrams via LLMs, allowing you to catch syntax errors immediately and feed precise parse errors back to the model for self-correction.

---

## Why Mmdlint?

* **No Headless Browser Required:** Traditional Mermaid validation tools (like `mermaid-cli` / `mmdc`) launch Chromium. In Docker, production Rails servers, Heroku/Kamal, and sandboxed CI runners, Chromium is heavy, slow, and frequently crashes or fails due to missing shared libraries.
* **Mermaid Native Parser:** Uses Mermaid's own parser (`mermaid.parse`) inside an in-process `jsdom` DOM. It catches the exact same strict syntax errors that break client-side rendering.
* **Auto-Normalization for LLMs:** Raw LLM outputs (e.g. `graph TD\n  A -->`) often omit Markdown fences. Mmdlint auto-detects and handles both raw diagrams and full Markdown documents.
* **Structured JSON over Stdin:** Bundles a zero-disk-I/O runner communicating over `Open3` stdin/stdout. No temporary files or fragile terminal regex parsing needed.

---

## Installation

Add this line to your application's `Gemfile`:

```ruby
gem "mmdlint"
```

And execute:

```bash
bundle install
```

### Node.js Dependency

Ensure Node.js (`>= 18`) is available in your environment, and install `@sysid/mmdlint`:

```bash
# In your Rails project root:
npm install --save-dev @sysid/mmdlint
# or:
yarn add --dev @sysid/mmdlint
# or globally:
npm install -g @sysid/mmdlint
```

---

## Usage

### 1. Basic Diagram Validation

```ruby
require "mmdlint"

# Valid diagram
result = Mmdlint.lint("graph TD\n  A[Start] --> B[Finish]")
result.valid? # => true
result.errors # => []

# Invalid diagram
result = Mmdlint.lint("graph TD\n  A -->")
result.valid? # => false
result.errors 
# => ["Parse error on line 3:\ngraph TD  A -->\n---------------^\nExpecting 'AMP', ..., got 'EOF'"]
```

### 2. Convenience Helpers

```ruby
# Boolean predicate
if Mmdlint.valid?(llm_output)
  render_diagram(llm_output)
end

# Strict validation (raises Mmdlint::ValidationError if invalid)
begin
  Mmdlint.validate!(llm_output)
rescue Mmdlint::ValidationError => e
  logger.warn("Mermaid error: #{e.message}")
  retry_with_llm(error: e.result.error_message)
end
```

### 3. Programmatic Autofixing (Instant & Free)

Auto-correct common LLM syntax mistakes (unquoted parentheses/colons in node labels, missing diagram headers, unclosed subgraphs, single-dash arrows `->`, unescaped sequence semicolons) before rendering:

```ruby
raw_llm = <<~MMD
  A[User (Admin)] ->|Status: OK (200)| B[(Database: /v1)]
MMD

# Auto-fix and validate in one step:
autofix = Mmdlint.fix_and_validate(raw_llm)
autofix.valid?      # => true
autofix.fixed?      # => true
autofix.fixed_code
# => "flowchart TD\n  A[\"User (Admin)\"] -->|\"Status: OK (200)\"| B[(\"Database: /v1\")]"

# Or sanitize the code directly:
clean_code = Mmdlint.fix(raw_llm)
```

### 4. Markdown Validation & Autofixing (Multiple Diagrams)

Validate documents containing one or more fenced ` ```mermaid ` blocks:

```ruby
markdown = <<~MD
  # System Architecture

  ```mermaid
  graph TD
    User --> RailsApp
  ```

  And here is the database flow:

  ```mermaid
  sequenceDiagram
    RailsApp->>PostgreSQL: Query
  ```
MD

result = Mmdlint.lint_markdown(markdown)
result.valid? # => true
result.blocks.each do |block|
  puts "Block ##{block.index} at line #{block.start_line}: #{block.valid? ? 'OK' : block.error}"
end
```

---

## Rails Integration Examples

### LLM Self-Correction Loop

When generating diagrams via OpenAI, Anthropic, or Gemini in your Rails app:

```ruby
class MermaidGeneratorService
  MAX_RETRIES = 3

  def self.generate_diagram(prompt)
    messages = [{ role: "user", content: prompt }]

    MAX_RETRIES.times do |attempt|
      response = ClaudeClient.chat(messages: messages)
      diagram_code = response.dig("content", 0, "text")

      validation = Mmdlint.lint(diagram_code)
      return diagram_code if validation.valid?

      # Feed the exact parse error back to the LLM to fix itself
      messages << { role: "assistant", content: diagram_code }
      messages << {
        role: "user",
        content: "The generated Mermaid diagram contains a syntax error:\n\n" \
                 "#{validation.error_message}\n\n" \
                 "Please fix the diagram syntax and return ONLY the corrected Mermaid code."
      }
    end

    raise "Failed to generate valid Mermaid diagram after #{MAX_RETRIES} attempts."
  end
end
```

### ActiveModel Custom Validator

```ruby
class MermaidDiagramValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?

    result = Mmdlint.lint(value)
    unless result.valid?
      record.errors.add(attribute, options[:message] || "contains syntax errors: #{result.errors.first}")
    end
  rescue Mmdlint::Error => e
    record.errors.add(attribute, "could not be validated: #{e.message}")
  end
end

class ArchitectureDoc < ApplicationRecord
  validates :mermaid_content, mermaid_diagram: true
end
```

---

## Configuration

You can customize Mmdlint in an initializer (e.g. `config/initializers/mmdlint.rb`):

```ruby
Mmdlint.configure do |config|
  # Path to Node.js binary (default: "node")
  config.node_path = ENV.fetch("NODE_PATH", "node")

  # Execution mode: :runner (bundled JSON runner, default) or :cli (calls `mmdlint` executable)
  config.mode = :runner

  # Timeout in seconds (default: 15)
  config.timeout = 10

  # Custom directory to resolve node_modules from (default: Dir.pwd)
  config.working_directory = Rails.root.to_s if defined?(Rails)
end
```

---

## Error Handling

All gem exceptions inherit from `Mmdlint::Error`:

| Exception | Cause |
|---|---|
| `Mmdlint::NodeNotFoundError` | `node` executable cannot be found in `$PATH`. |
| `Mmdlint::DependencyError` | Node package `@sysid/mmdlint` is not installed or cannot be resolved. |
| `Mmdlint::TimeoutError` | Validation exceeded `config.timeout`. |
| `Mmdlint::ExecutionError` | Runner or CLI exited unexpectedly. |
| `Mmdlint::ValidationError` | Raised by `Mmdlint.validate!` when syntax errors exist. Includes `.result`. |

---

## Development

After checking out the repo:

```bash
bin/setup # or bundle install && npm install
bundle exec rake spec
```

To release a new version:

```bash
bundle exec rake build
```

---

## License

Available as open source under the terms of the [MIT License](LICENSE.txt).
