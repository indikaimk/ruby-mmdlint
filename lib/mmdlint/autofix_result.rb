# frozen_string_literal: true

module Mmdlint
  # Holds the outcome of an autofix and subsequent validation run.
  class AutofixResult
    attr_reader :original_code, :fixed_code, :result

    def initialize(original_code:, fixed_code:, result:)
      @original_code = original_code
      @fixed_code = fixed_code
      @result = result
    end

    def valid?
      @result.valid?
    end

    def invalid?
      @result.invalid?
    end

    # Returns true if the autofixer modified the original input.
    def fixed?
      @original_code != @fixed_code
    end

    def errors
      @result.errors
    end

    def error_message
      @result.error_message
    end

    def blocks
      @result.blocks
    end

    def to_h
      {
        valid: valid?,
        fixed: fixed?,
        original_code: original_code,
        fixed_code: fixed_code,
        errors: errors,
        blocks: blocks.map(&:to_h)
      }
    end
  end
end
