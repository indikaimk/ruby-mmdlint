# frozen_string_literal: true

module Mmdlint
  # Holds the outcome of a validation run.
  class Result
    attr_reader :type, :blocks, :errors, :raw_output

    def initialize(valid:, errors: [], blocks: [], type: :diagram, raw_output: nil)
      @valid = !!valid
      @errors = Array(errors).map(&:to_s)
      @blocks = Array(blocks)
      @type = type.to_sym
      @raw_output = raw_output
    end

    def valid?
      @valid
    end

    def invalid?
      !valid?
    end

    # Returns a combined string of all syntax errors, ideal for feedback to an LLM.
    def error_message
      errors.join("\n\n")
    end

    def to_h
      {
        valid: valid?,
        type: type,
        errors: errors,
        blocks: blocks.map(&:to_h)
      }
    end
  end
end
