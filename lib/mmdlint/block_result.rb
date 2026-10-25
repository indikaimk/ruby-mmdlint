# frozen_string_literal: true

module Mmdlint
  # Represents validation results for a single Mermaid diagram block.
  class BlockResult
    attr_reader :index, :start_line, :code, :error

    def initialize(index:, start_line:, code:, ok:, error: nil)
      @index = index
      @start_line = start_line
      @code = code
      @ok = !!ok
      @error = error
    end

    def valid?
      @ok
    end

    def invalid?
      !valid?
    end

    def to_h
      {
        index: index,
        start_line: start_line,
        code: code,
        valid: valid?,
        error: error
      }
    end
  end
end
