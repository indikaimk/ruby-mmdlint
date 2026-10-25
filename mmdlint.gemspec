# frozen_string_literal: true

require_relative "lib/mmdlint/version"

Gem::Specification.new do |spec|
  spec.name = "mmdlint"
  spec.version = Mmdlint::VERSION
  spec.authors = ["Indika"]
  spec.email = ["indika@example.com"]

  spec.summary = "Ruby wrapper for Node.js mmdlint (Mermaid diagram linter)"
  spec.description = "A headless syntax linter for Mermaid diagrams and Markdown documents via Node.js mmdlint, ideal for Rails apps validating LLM-generated diagrams."
  spec.homepage = "https://github.com/indika/ruby-mmdlint"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.glob("{lib}/**/*", File::FNM_DOTMATCH).reject { |f| File.directory?(f) } + ["README.md", "LICENSE.txt"].select { |f| File.exist?(f) }
  spec.require_paths = ["lib"]
end
