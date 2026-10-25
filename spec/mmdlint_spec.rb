# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mmdlint do
  it "has a version number" do
    expect(Mmdlint::VERSION).not_to be_nil
  end

  describe ".lint" do
    it "auto-detects and validates raw diagram code" do
      code = "graph LR\n  A --> B"
      result = described_class.lint(code)

      expect(result).to be_valid
      expect(result.type).to eq(:diagram)
      expect(result.errors).to be_empty
    end

    it "auto-detects and validates markdown containing ```mermaid fences" do
      md = <<~MD
        # Header
        ```mermaid
        sequenceDiagram
          Alice->>Bob: Hello
        ```
      MD
      result = described_class.lint(md)

      expect(result).to be_valid
      expect(result.type).to eq(:markdown)
      expect(result.blocks.size).to eq(1)
    end
  end

  describe ".valid?" do
    it "returns true for a valid diagram" do
      expect(described_class.valid?("graph TD\n  A --> B")).to be(true)
    end

    it "returns false for an invalid diagram" do
      expect(described_class.valid?("graph TD\n  A -->")).to be(false)
    end
  end

  describe ".validate!" do
    it "returns true when valid" do
      expect(described_class.validate!("graph TD\n  A --> B")).to be(true)
    end

    it "raises ValidationError with result when invalid" do
      expect {
        described_class.validate!("graph TD\n  A -->")
      }.to raise_error(Mmdlint::ValidationError) { |error|
        expect(error.result).not_to be_nil
        expect(error.result.errors).not_to be_empty
        expect(error.message).to include("Parse error")
      }
    end
  end

  describe ".lint_diagram" do
    it "validates a valid diagram" do
      result = described_class.lint_diagram("classDiagram\n  class Animal")
      expect(result).to be_valid
      expect(result.type).to eq(:diagram)
    end

    it "reports error for invalid diagram syntax" do
      result = described_class.lint_diagram("classDiagram\n  class")
      expect(result).not_to be_valid
      expect(result.errors.first).to include("Parse error")
    end
  end

  describe ".lint_markdown" do
    it "extracts and validates multiple blocks in markdown" do
      md = <<~MD
        # Spec

        ```mermaid
        graph TD
          A --> B
        ```

        ```mermaid
        pie title Pets
          "Dogs" : 386
          "Cats" : 85
        ```
      MD

      result = described_class.lint_markdown(md)
      expect(result).to be_valid
      expect(result.blocks.size).to eq(2)
      expect(result.blocks.map(&:valid?)).to eq([true, true])
    end
  end

  describe "Result and BlockResult objects" do
    it "converts Result and BlockResult to hash" do
      result = described_class.lint("graph TD\n  A --> B")
      hash = result.to_h

      expect(hash[:valid]).to be(true)
      expect(hash[:type]).to eq(:diagram)
      expect(hash[:errors]).to eq([])
      expect(hash[:blocks].first[:index]).to eq(1)
      expect(hash[:blocks].first[:valid]).to be(true)
    end
  end
end
