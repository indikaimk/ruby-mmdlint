# frozen_string_literal: true

module Mmdlint
  # Base error class for all Mmdlint exceptions.
  class Error < StandardError; end

  # Raised when Node.js executable cannot be found in PATH.
  class NodeNotFoundError < Error; end

  # Raised when Node.js package @sysid/mmdlint is missing or cannot be resolved.
  class DependencyError < Error; end

  # Raised when the validation process exceeds the configured timeout.
  class TimeoutError < Error; end

  # Raised when the runner or CLI crashes or exits unexpectedly.
  class ExecutionError < Error; end

  # Raised by Mmdlint.validate! when validation fails.
  class ValidationError < Error
    attr_reader :result

    def initialize(message, result = nil)
      super(message)
      @result = result
    end
  end
end
