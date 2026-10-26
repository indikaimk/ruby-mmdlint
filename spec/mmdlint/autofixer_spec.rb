# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mmdlint::Autofixer do
  describe ".fix_diagram" do
    it "quotes node labels containing parentheses, colons, and special characters" do
      code = <<~MMD
        flowchart TD
          A[User (Admin)] --> B(Round /path)
          B --> C{Is it (Ready)?}
          C --> D[(DB: /users)]
          D --> E([Stadium (Shape)])
          E --> F((Circle: 1))
          F --> G{{Hex: 2}}
          G --> H[[Sub: 3]]
          H --> I>Flag: 4]
      MMD

      fixed = described_class.fix_diagram(code)

      expect(fixed).to include('A["User (Admin)"]')
      expect(fixed).to include('B("Round /path")')
      expect(fixed).to include('C{"Is it (Ready)?"}')
      expect(fixed).to include('D[("DB: /users")]')
      expect(fixed).to include('E(["Stadium (Shape)"])')
      expect(fixed).to include('F(("Circle: 1"))')
      expect(fixed).to include('G{{"Hex: 2"}}')
      expect(fixed).to include('H[["Sub: 3"]]')
      expect(fixed).to include('I>"Flag: 4"]')

      # The fixed diagram must be valid!
      result = Mmdlint.lint_diagram(fixed)
      expect(result).to be_valid
    end

    it "preserves labels that are already double-quoted" do
      code = 'flowchart TD\n  A["Already (Quoted)"] --> B["Another One"]'
      fixed = described_class.fix_diagram(code)

      expect(fixed).to include('A["Already (Quoted)"]')
      expect(fixed).to include('B["Another One"]')
    end

    it "quotes pipe labels on edges containing special characters" do
      code = <<~MMD
        flowchart TD
          A -->|Status: OK (200)| B
      MMD

      fixed = described_class.fix_diagram(code)
      expect(fixed).to include('A -->|"Status: OK (200)"| B')

      result = Mmdlint.lint_diagram(fixed)
      expect(result).to be_valid
    end

    it "quotes subgraph titles with brackets" do
      code = <<~MMD
        flowchart TD
          subgraph Cluster1 [Backend (API)]
            A --> B
          end
      MMD

      fixed = described_class.fix_diagram(code)
      expect(fixed).to include('subgraph Cluster1 ["Backend (API)"]')

      result = Mmdlint.lint_diagram(fixed)
      expect(result).to be_valid
    end

    it "balances unclosed subgraph blocks" do
      code = <<~MMD
        flowchart TD
          subgraph Outer
            subgraph Inner
              A --> B
      MMD

      fixed = described_class.fix_diagram(code)
      expect(fixed.scan(/^\s*end\b/).size).to eq(2)

      result = Mmdlint.lint_diagram(fixed)
      expect(result).to be_valid
    end

    it "normalizes single-dash arrows to double-dash arrows in flowcharts" do
      code = <<~MMD
        flowchart TD
          A -> B
          B ->|Pipe| C
          C --->> D
      MMD

      fixed = described_class.fix_diagram(code)
      expect(fixed).to include("A --> B")
      expect(fixed).to include("B -->|\"Pipe\"| C")
      expect(fixed).to include("C --> D")

      result = Mmdlint.lint_diagram(fixed)
      expect(result).to be_valid
    end

    it "escapes unescaped semicolons in sequence diagram messages" do
      code = <<~MMD
        sequenceDiagram
          Alice->>Bob: Hello; how are you?
      MMD

      fixed = described_class.fix_diagram(code)
      expect(fixed).to include("Hello&#59; how are you?")

      result = Mmdlint.lint_diagram(fixed)
      expect(result).to be_valid
    end

    it "prepends flowchart TD when diagram header is missing" do
      code = "A[Start] --> B[End]"
      fixed = described_class.fix_diagram(code)

      expect(fixed).to start_with("flowchart TD")
      result = Mmdlint.lint_diagram(fixed)
      expect(result).to be_valid
    end

    it "strips surrounding conversational markdown and code fences" do
      raw_llm = <<~TXT
        Here is the diagram you requested:

        ```mermaid
        flowchart TD
          A[Start] --> B[End]
        ```

        Hope this helps!
      TXT

      fixed = described_class.fix_diagram(raw_llm)
      expect(fixed).to eq("flowchart TD\n  A[\"Start\"] --> B[\"End\"]")
    end

    it "escapes unescaped internal double quotes inside @{ ... } metadata labels" do
      code = <<~MMD
        flowchart TD
          nat@{ icon: "aws:ec2", label: "NAT Gateway "$$"" }
      MMD

      fixed = described_class.fix_diagram(code)
      expect(fixed).to include('label: "NAT Gateway \"$$\""')

      result = Mmdlint.lint_diagram(fixed)
      expect(result).to be_valid
    end
  end

  describe ".fix_markdown" do
    it "corrects all mermaid code blocks inside a markdown document" do
      markdown = <<~MD
        # Architecture

        ```mermaid
        flowchart TD
          A[Client (Browser)] -> B[Server (API)]
        ```

        Some explanation in between.

        ```mermaid
        sequenceDiagram
          User->>Server: Query; search
        ```
      MD

      fixed_md = described_class.fix_markdown(markdown)

      expect(fixed_md).to include('A["Client (Browser)"] --> B["Server (API)"]')
      expect(fixed_md).to include("Query&#59; search")
      expect(fixed_md).to include("# Architecture")
      expect(fixed_md).to include("Some explanation in between.")

      result = Mmdlint.lint_markdown(fixed_md)
      expect(result).to be_valid
      expect(result.blocks.size).to eq(2)
    end
  end

  describe "Mmdlint.fix_and_validate" do
    it "fixes an invalid diagram and returns an AutofixResult" do
      broken = "A[Client (Browser)] -> B[Server (API)]"

      autofix = Mmdlint.fix_and_validate(broken)

      expect(autofix).to be_valid
      expect(autofix).to be_fixed
      expect(autofix.original_code).to eq(broken)
      expect(autofix.fixed_code).to include('A["Client (Browser)"] --> B["Server (API)"]')
      expect(autofix.errors).to be_empty
    end
  end
end
