# frozen_string_literal: true

module Mmdlint
  # Programmatically corrects common LLM-generated Mermaid syntax errors.
  class Autofixer
    DIAGRAM_HEADERS = %w[
      flowchart
      graph
      sequenceDiagram
      classDiagram
      stateDiagram
      stateDiagram-v2
      erDiagram
      gantt
      pie
      gitGraph
      mindmap
      timeline
      sankey
      quadrantChart
      xychart
      kanban
      block
      architecture
      c4
    ].freeze

    SHAPES_REGEX = Regexp.new(
      "(?<![\\|\"])\\b([a-zA-Z0-9_.-]+)\\s*(" \
      "\\[\\((.*?)\\s*\\)\\]|" \
      "\\(\\[(.*?)\\s*\\]\\)|" \
      "\\[\\[(.*?)\\s*\\]\\]|" \
      "\\(\\((.*?)\\s*\\)\\)|" \
      "\\{\\{(.*?)\\s*\\}\\}|" \
      "\\[(.*?)\\s*\\]|" \
      "\\((.*?)\\s*\\)|" \
      "\\{(.*?)\\s*\\}|" \
      ">(.*?)\\s*\\]" \
      ")"
    )

    class << self
      def fix(input, type: nil)
        new.fix(input, type: type)
      end

      def fix_diagram(code)
        new.fix_diagram(code)
      end

      def fix_markdown(markdown)
        new.fix_markdown(markdown)
      end
    end

    def fix(input, type: nil)
      resolved_type = type || (input.to_s.match?(Mmdlint::MERMAID_FENCE_REGEX) ? :markdown : :diagram)
      if resolved_type == :markdown
        fix_markdown(input)
      else
        fix_diagram(input)
      end
    end

    def fix_markdown(markdown)
      markdown.to_s.gsub(/^[ \t]*```[ \t]*mermaid[ \t]*\r?\n([\s\S]*?)^[ \t]*```[ \t]*$/m) do
        code = $1
        "```mermaid\n#{fix_diagram(code).strip}\n```"
      end
    end

    def fix_diagram(code)
      cleaned = extract_diagram_content(code)
      return cleaned if cleaned.empty?

      diagram_type = detect_diagram_type(cleaned)

      # 1. Ensure a diagram header exists if completely missing
      if diagram_type == :unknown
        cleaned = "flowchart TD\n#{cleaned}"
        diagram_type = :flowchart
      end

      # 2. Diagram-type specific fixes
      if %i[flowchart graph].include?(diagram_type)
        cleaned = fix_flowchart(cleaned)
      elsif diagram_type == :sequence
        cleaned = fix_sequence(cleaned)
      end

      cleaned.strip
    end

    private

    # Strips conversational LLM markdown fences or preamble text if present
    def extract_diagram_content(code)
      str = code.to_s.strip

      # If wrapped in ```mermaid ... ```
      if str =~ /\A.*?```(?:mermaid)?\s*\r?\n(.*?)```.*?\z/m
        return $1.strip
      end

      # Strip leading/trailing lone fences
      str = str.gsub(/\A```[a-z]*\s*\n?/i, "").gsub(/\n?```\s*\z/, "")
      str.strip
    end

    def detect_diagram_type(code)
      first_meaningful_line = code.each_line.map(&:strip).reject { |l| l.empty? || l.start_with?("%%") }.first
      return :unknown unless first_meaningful_line

      first_word = first_meaningful_line.split(/\s+/).first
      case first_word
      when "flowchart"
        :flowchart
      when "graph"
        :graph
      when "sequenceDiagram"
        :sequence
      when "classDiagram"
        :class
      when "stateDiagram", "stateDiagram-v2"
        :state
      when "erDiagram"
        :er
      when *DIAGRAM_HEADERS
        first_word.to_sym
      else
        :unknown
      end
    end

    def fix_flowchart(code)
      s = code.dup
      masks = {}

      # 1. Normalize and mask metadata blocks (@{ ... })
      s.gsub!(/@\{\s*.*?\s*\}/m) do |meta_block|
        fixed_meta = fix_metadata_attributes(meta_block)
        placeholder = "__MMD_META_#{masks.size}__"
        masks[placeholder] = fixed_meta
        placeholder
      end

      # 2. Normalize and mask subgraph titles
      s.gsub!(/subgraph\s+([a-zA-Z0-9_.-]+)\s*\[\s*(.*?)\s*\]/) do
        id = $1
        title = $2
        placeholder = "__MMD_SUBGRAPH_#{masks.size}__"
        masks[placeholder] = "subgraph #{id} [" + quote_label(title) + "]"
        placeholder
      end

      # 3. Normalize and mask edge pipe labels (|Condition (with parens)| -> |"Condition (with parens)"|)
      s.gsub!(/\|([^|\n\r]+)\|/) do
        placeholder = "__MMD_PIPE_#{masks.size}__"
        masks[placeholder] = "|" + quote_label($1) + "|"
        placeholder
      end

      # 4. Auto-quote node labels in shapes
      s.gsub!(SHAPES_REGEX) do
        id = $1
        full = $2

        if full.start_with?("[(") && full.end_with?(")]")
          "#{id}[(" + quote_label(full[2..-3]) + ")]"
        elsif full.start_with?("([") && full.end_with?("])")
          "#{id}([" + quote_label(full[2..-3]) + "])"
        elsif full.start_with?("[[") && full.end_with?("]]")
          "#{id}[[" + quote_label(full[2..-3]) + "]]"
        elsif full.start_with?("((") && full.end_with?("))")
          "#{id}((" + quote_label(full[2..-3]) + "))"
        elsif full.start_with?("{{") && full.end_with?("}}")
          "#{id}{{" + quote_label(full[2..-3]) + "}}"
        elsif full.start_with?("[") && full.end_with?("]")
          "#{id}[" + quote_label(full[1..-2]) + "]"
        elsif full.start_with?("(") && full.end_with?(")")
          "#{id}(" + quote_label(full[1..-2]) + ")"
        elsif full.start_with?("{") && full.end_with?("}")
          "#{id}{" + quote_label(full[1..-2]) + "}"
        elsif full.start_with?(">") && full.end_with?("]")
          "#{id}>" + quote_label(full[1..-2]) + "]"
        else
          $&
        end
      end

      # 5. Restore all masks
      masks.each do |placeholder, original|
        s.gsub!(placeholder, original)
      end

      # 6. Normalize single dash arrow `->` to `-->` in flowchart (e.g. `A -> B` or `A ->|label| B`)
      s.gsub!(/(?<=\s)->(?=\||\s)/, "-->")
      # Normalize hallucinated sequence arrows `--->>` in flowchart to `-->`
      s.gsub!(/(?<=\s)--->>(?=\||\s)/, "-->")

      # 7. Balance unclosed subgraphs
      subgraph_count = s.scan(/^\s*subgraph\b/).size
      end_count = s.scan(/^\s*end\b/).size
      if subgraph_count > end_count
        s << "\n" unless s.end_with?("\n")
        (subgraph_count - end_count).times { s << "  end\n" }
      end

      s
    end

    def fix_sequence(code)
      lines = code.split("\n")
      fixed_lines = lines.map do |line|
        # In sequence diagrams: Actor->>Actor: Message; with semicolon
        if line =~ /^(\s*[a-zA-Z0-9_]+(?:\s*(?:->>|-->>|->|-->)\s*)[a-zA-Z0-9_]+\s*:\s*)(.*)$/
          prefix = $1
          message = $2
          # Replace unescaped semicolons with &#59;
          sanitized_message = message.gsub(/&#\d+;|;/) do |match|
            match == ";" ? "&#59;" : match
          end
          "#{prefix}#{sanitized_message}"
        else
          line
        end
      end
      fixed_lines.join("\n")
    end

    def fix_metadata_attributes(block)
      block.gsub(/(@\{\s*)(.*?)(\s*\})/m) do
        prefix = $1
        body = $2
        suffix = $3

        entries = body.split(/(?<=[a-zA-Z0-9_\x22\x27])\s*,\s*(?=[a-zA-Z0-9_]+\s*:)/)
        fixed_entries = entries.map do |entry|
          if entry =~ /\A\s*([a-zA-Z0-9_]+)\s*:\s*\"(.*)\"\s*\z/m
            key = $1
            val = $2
            escaped_val = val.gsub(/(?<!\\)\"/, "\\\"")
            "#{key}: \"#{escaped_val}\""
          else
            entry
          end
        end

        "#{prefix}#{fixed_entries.join(", ")}#{suffix}"
      end
    end

    def quote_label(str)
      s = str.strip
      return str if s.start_with?('"') && s.end_with?('"')

      # Escape any internal unescaped double quotes
      escaped = s.gsub(/(?<!\\)"/, '\"')
      "\"#{escaped}\""
    end
  end
end
