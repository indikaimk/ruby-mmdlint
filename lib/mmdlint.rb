# frozen_string_literal: true

require_relative "mmdlint/version"
require_relative "mmdlint/errors"
require_relative "mmdlint/block_result"
require_relative "mmdlint/result"
require_relative "mmdlint/configuration"
require_relative "mmdlint/runner"
require_relative "mmdlint/cli_runner"
require_relative "mmdlint/autofix_result"
require_relative "mmdlint/autofixer"

module Mmdlint
  MERMAID_FENCE_REGEX = /^[ \t]*```[ \t]*mermaid/m

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    # Validates Mermaid code or Markdown. Auto-detects diagram vs markdown if type is omitted.
    #
    # @param input [String] Mermaid diagram source code or Markdown string.
    # @param type [Symbol, nil] :diagram, :markdown, or nil for auto-detection.
    # @return [Mmdlint::Result]
    def lint(input, type: nil)
      resolved_type = type || detect_type(input)
      runner = select_runner
      runner.run(input, type: resolved_type)
    end

    # Explicitly validates a single Mermaid diagram body.
    #
    # @param code [String] Mermaid diagram code.
    # @return [Mmdlint::Result]
    def lint_diagram(code)
      lint(code, type: :diagram)
    end

    # Explicitly validates all Mermaid blocks in a Markdown string.
    #
    # @param markdown [String] Markdown text containing ```mermaid blocks.
    # @return [Mmdlint::Result]
    def lint_markdown(markdown)
      lint(markdown, type: :markdown)
    end

    # Returns true if input has no syntax errors, false otherwise.
    #
    # @param input [String] Mermaid diagram or Markdown text.
    # @param type [Symbol, nil] :diagram, :markdown, or nil.
    # @return [Boolean]
    def valid?(input, type: nil)
      lint(input, type: type).valid?
    end

    # Validates input and returns true if valid, or raises Mmdlint::ValidationError.
    #
    # @param input [String] Mermaid diagram or Markdown text.
    # @param type [Symbol, nil] :diagram, :markdown, or nil.
    # @return [true]
    # @raise [Mmdlint::ValidationError]
    def validate!(input, type: nil)
      result = lint(input, type: type)
      return true if result.valid?

      raise ValidationError.new("Mermaid validation failed:\n#{result.error_message}", result)
    end

    # Programmatically corrects common syntax errors in Mermaid diagrams or Markdown.
    #
    # @param input [String] Mermaid diagram source code or Markdown text.
    # @param type [Symbol, nil] :diagram, :markdown, or nil for auto-detection.
    # @return [String] Sanitized and corrected Mermaid code or Markdown.
    def fix(input, type: nil)
      Autofixer.fix(input, type: type)
    end

    # Programmatically corrects common syntax errors and validates the corrected result.
    #
    # @param input [String] Mermaid diagram source code or Markdown text.
    # @param type [Symbol, nil] :diagram, :markdown, or nil for auto-detection.
    # @return [Mmdlint::AutofixResult]
    def fix_and_validate(input, type: nil)
      fixed_code = fix(input, type: type)
      res = lint(fixed_code, type: type)

      AutofixResult.new(
        original_code: input.to_s,
        fixed_code: fixed_code,
        result: res
      )
    end

    private

    def detect_type(input)
      input.to_s.match?(MERMAID_FENCE_REGEX) ? :markdown : :diagram
    end

    def select_runner
      case configuration.mode
      when :cli
        CliRunner.new(configuration)
      else
        Runner.new(configuration)
      end
    end
  end
end
