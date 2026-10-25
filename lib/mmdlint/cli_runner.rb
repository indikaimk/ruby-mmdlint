# frozen_string_literal: true

require "open3"
require "tempfile"
require "timeout"

module Mmdlint
  # Executes validation using the standalone mmdlint CLI binary.
  class CliRunner
    attr_reader :configuration

    OK_PATTERN = /\Aok\s+\S+:(\d+)\s+#(\d+)\s+\[(.*?)\]\z/
    FAIL_PATTERN = /\AFAIL\s+\S+:(\d+)\s+#(\d+)\s+\[(.*?)\]:\s*(.*)\z/

    def initialize(configuration = Mmdlint.configuration)
      @configuration = configuration
    end

    def run(content, type: :diagram)
      # Ensure content has mermaid code fence if linting a raw diagram
      markdown_content = if type == :diagram
        ensure_mermaid_fence(content)
      else
        content.to_s
      end

      Tempfile.create(["mmdlint_", ".md"]) do |file|
        file.write(markdown_content)
        file.flush

        cmd = [configuration.cli_path, file.path]
        stdout, stderr, status = execute_command(cmd)

        parse_cli_output(stdout, stderr, status, type: type)
      end
    end

    private

    def ensure_mermaid_fence(content)
      trimmed = content.to_s.strip
      if trimmed.start_with?("```mermaid")
        content.to_s
      else
        "```mermaid\n#{content}\n```\n"
      end
    end

    def execute_command(cmd)
      stdout_str = +""
      stderr_str = +""
      status = nil

      Open3.popen3(*cmd, chdir: configuration.resolved_working_directory) do |stdin, stdout, stderr, wait_thr|
        pid = wait_thr.pid
        begin
          stdin.close
          Timeout.timeout(configuration.timeout, TimeoutError, "CLI validation timed out after #{configuration.timeout}s") do
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
            # Process already finished
          end
          raise
        ensure
          stdout.close unless stdout.closed?
          stderr.close unless stderr.closed?
        end
      end

      [stdout_str, stderr_str, status]
    rescue Errno::ENOENT => e
      raise ExecutionError, "CLI executable '#{configuration.cli_path}' was not found: #{e.message}"
    end

    def parse_cli_output(stdout, stderr, status, type:)
      combined_output = "#{stdout}\n#{stderr}".strip
      blocks = []
      errors = []

      combined_output.each_line do |line|
        line = line.strip

        if (match = line.match(FAIL_PATTERN))
          start_line = match[1].to_i
          index = match[2].to_i
          summary = match[3]
          error_msg = match[4]

          errors << error_msg
          blocks << BlockResult.new(
            index: index,
            start_line: start_line,
            code: summary,
            ok: false,
            error: error_msg
          )
        elsif (match = line.match(OK_PATTERN))
          start_line = match[1].to_i
          index = match[2].to_i
          summary = match[3]

          blocks << BlockResult.new(
            index: index,
            start_line: start_line,
            code: summary,
            ok: true,
            error: nil
          )
        end
      end

      # If CLI failed with non-zero but neither ok nor fail matched, record generic error
      if !status&.success? && blocks.empty?
        err = stderr.strip.empty? ? stdout.strip : stderr.strip
        raise ExecutionError, "CLI exited with status #{status&.exitstatus}: #{err}"
      end

      valid = blocks.all?(&:valid?) && errors.empty?

      Result.new(
        valid: valid,
        errors: errors,
        blocks: blocks,
        type: type,
        raw_output: combined_output
      )
    end
  end
end
