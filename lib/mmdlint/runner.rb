# frozen_string_literal: true

require "open3"
require "json"
require "timeout"

module Mmdlint
  # Executes validation using the bundled Node.js runner over stdin/stdout.
  class Runner
    attr_reader :configuration

    def initialize(configuration = Mmdlint.configuration)
      @configuration = configuration
    end

    def run(content, type: :diagram)
      payload = JSON.generate({
        type: type.to_s,
        content: content.to_s,
        working_directory: configuration.resolved_working_directory
      })

      cmd = [configuration.node_path, configuration.runner_path]

      stdout, stderr, status = execute_command(cmd, payload)

      handle_output(stdout, stderr, status)
    end

    private

    def execute_command(cmd, stdin_data)
      stdout_str = +""
      stderr_str = +""
      status = nil

      Open3.popen3(*cmd, chdir: configuration.resolved_working_directory) do |stdin, stdout, stderr, wait_thr|
        pid = wait_thr.pid
        begin
          Timeout.timeout(configuration.timeout, TimeoutError, "Validation timed out after #{configuration.timeout}s") do
            if stdin_data && !stdin_data.empty?
              stdin.write(stdin_data)
            end
            stdin.close

            stdout_thr = Thread.new do
              Thread.current.report_on_exception = false
              stdout.read
            rescue IOError
              ""
            end

            stderr_thr = Thread.new do
              Thread.current.report_on_exception = false
              stderr.read
            rescue IOError
              ""
            end

            stdout_str = stdout_thr.value || ""
            stderr_str = stderr_thr.value || ""
            status = wait_thr.value
          end
        rescue TimeoutError
          begin
            Process.kill("KILL", pid)
          rescue Errno::ESRCH
            # Process already exited
          end
          raise
        ensure
          stdin.close unless stdin.closed?
          stdout.close unless stdout.closed?
          stderr.close unless stderr.closed?
        end
      end

      [stdout_str, stderr_str, status]
    rescue Errno::ENOENT => e
      raise NodeNotFoundError, "Node.js executable '#{configuration.node_path}' was not found: #{e.message}"
    end

    def handle_output(stdout, stderr, status)
      if status&.exitstatus == 2
        error_info = parse_json_safely(stderr) || parse_json_safely(stdout)
        msg = error_info && error_info["message"] ? error_info["message"] : "Missing dependency @sysid/mmdlint"
        raise DependencyError, msg
      end

      unless status&.success?
        error_info = parse_json_safely(stderr) || parse_json_safely(stdout)
        msg = error_info && error_info["message"] ? error_info["message"] : "Validation process failed (exit #{status&.exitstatus}): #{stderr.strip}"
        raise ExecutionError, msg
      end

      data = JSON.parse(stdout)

      blocks = (data["blocks"] || []).map do |b|
        BlockResult.new(
          index: b["index"],
          start_line: b["startLine"],
          code: b["code"],
          ok: b["ok"],
          error: b["error"]
        )
      end

      Result.new(
        valid: data["ok"],
        errors: data["errors"] || [],
        blocks: blocks,
        type: data["type"] || :diagram,
        raw_output: data
      )
    rescue JSON::ParserError => e
      raise ExecutionError, "Failed to parse runner output as JSON: #{e.message}\nOutput: #{stdout}"
    end

    def parse_json_safely(str)
      return nil if str.nil? || str.strip.empty?
      JSON.parse(str)
    rescue JSON::ParserError
      nil
    end
  end
end
