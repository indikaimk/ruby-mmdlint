# frozen_string_literal: true

module Mmdlint
  # Configuration options for Mmdlint execution.
  class Configuration
    DEFAULT_RUNNER_PATH = File.expand_path("runner.mjs", __dir__).freeze

    attr_accessor :node_path, :runner_path, :cli_path, :mode, :timeout, :working_directory

    def initialize
      @node_path = "node"
      @runner_path = DEFAULT_RUNNER_PATH
      @cli_path = "mmdlint"
      @mode = :runner
      @timeout = 15
      @working_directory = nil
    end

    def resolved_working_directory
      @working_directory || Dir.pwd
    end
  end
end
