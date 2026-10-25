# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mmdlint::Runner do
  subject(:runner) { described_class.new }

  describe "#run with diagram" do
    it "returns valid Result for valid diagram" do
      code = <<~MMD
        graph TD
          A[Start] --> B[Finish]
      MMD

      result = runner.run(code, type: :diagram)

      expect(result).to be_valid
      expect(result.errors).to be_empty
      expect(result.blocks.size).to eq(1)
      expect(result.blocks.first).to be_valid
      expect(result.type).to eq(:diagram)
    end

    it "returns invalid Result with syntax errors for invalid diagram" do
      code = <<~MMD
        graph TD
          A -->
      MMD

      result = runner.run(code, type: :diagram)

      expect(result).not_to be_valid
      expect(result.errors).not_to be_empty
      expect(result.errors.first).to include("Parse error")
      expect(result.blocks.first).not_to be_valid
    end
  end

  describe "#run with markdown" do
    it "validates all fenced blocks in markdown" do
      markdown = <<~MD
        # Architecture

        ```mermaid
        graph LR
          Client --> Server
        ```

        Some middle text.

        ```mermaid
        sequenceDiagram
          Alice->>Bob: Hello
        ```
      MD

      result = runner.run(markdown, type: :markdown)

      expect(result).to be_valid
      expect(result.blocks.size).to eq(2)
      expect(result.blocks.all?(&:valid?)).to be(true)
      expect(result.blocks[0].start_line).to eq(3)
      expect(result.blocks[1].start_line).to eq(10)
    end

    it "captures failing blocks and their lines in markdown" do
      markdown = <<~MD
        # Broken Doc

        ```mermaid
        graph TD
          Valid --> Node
        ```

        ```mermaid
        graph TD
          Invalid -->
        ```
      MD

      result = runner.run(markdown, type: :markdown)

      expect(result).not_to be_valid
      expect(result.blocks.size).to eq(2)
      expect(result.blocks[0]).to be_valid
      expect(result.blocks[1]).not_to be_valid
      expect(result.blocks[1].error).to include("Parse error")
    end
  end

  describe "error handling" do
    it "raises NodeNotFoundError when node binary does not exist" do
      Mmdlint.configuration.node_path = "non_existent_node_bin_xyz"
      runner = described_class.new(Mmdlint.configuration)

      expect {
        runner.run("graph TD\n  A --> B")
      }.to raise_error(Mmdlint::NodeNotFoundError, /non_existent_node_bin_xyz/)
    end

    it "raises TimeoutError when execution exceeds timeout" do
      Mmdlint.configuration.timeout = 0.00001
      runner = described_class.new(Mmdlint.configuration)

      expect {
        runner.run("graph TD\n  A --> B")
      }.to raise_error(Mmdlint::TimeoutError)
    end
  end
end
