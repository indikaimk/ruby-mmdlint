# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mmdlint::CliRunner do
  let(:cli_binary) { File.expand_path("../../node_modules/.bin/mmdlint", __dir__) }

  before do
    Mmdlint.configuration.cli_path = cli_binary
  end

  subject(:cli_runner) { described_class.new(Mmdlint.configuration) }

  describe "#run with diagram" do
    it "auto-wraps raw diagram in mermaid fences and reports valid" do
      code = "graph TD\n  A --> B"
      result = cli_runner.run(code, type: :diagram)

      expect(result).to be_valid
      expect(result.errors).to be_empty
      expect(result.blocks.size).to eq(1)
      expect(result.blocks.first).to be_valid
    end

    it "reports errors when diagram has syntax error" do
      code = "graph TD\n  A -->"
      result = cli_runner.run(code, type: :diagram)

      expect(result).not_to be_valid
      expect(result.errors).not_to be_empty
      expect(result.errors.first).to include("Parse error")
    end
  end

  describe "#run with markdown" do
    it "validates markdown with fenced mermaid blocks" do
      markdown = <<~MD
        # Doc
        ```mermaid
        graph LR
          X --> Y
        ```
      MD

      result = cli_runner.run(markdown, type: :markdown)

      expect(result).to be_valid
      expect(result.blocks.size).to eq(1)
    end
  end

  describe "error handling" do
    it "raises ExecutionError when CLI executable is not found" do
      Mmdlint.configuration.cli_path = "non_existent_mmdlint_binary_xyz"
      runner = described_class.new(Mmdlint.configuration)

      expect {
        runner.run("graph TD\n  A --> B")
      }.to raise_error(Mmdlint::ExecutionError, /non_existent_mmdlint_binary_xyz/)
    end
  end
end
