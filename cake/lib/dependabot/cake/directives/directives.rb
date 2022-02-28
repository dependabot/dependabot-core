# frozen_string_literal: true

module Dependabot
  module Cake
    module Directives
      # Details of Cake preprocessor directives is at
      # https://cakebuild.net/docs/fundamentals/preprocessor-directives
      DIRECTIVE = /#(?<directive>addin|l|load|module|tool)/i.freeze
      CONTEXT   = /(?<context>[^"]+)/.freeze
      DIRECTIVE_LINE = /^#{DIRECTIVE}\s+"?#{CONTEXT}"?/.freeze

      @cake_directives = {}

      def self.for_cake_directive(directive)
        cake_directive = @cake_directives[directive.downcase]
        return cake_directive if cake_directive

        raise "Unsupported directive #{directive}"
      end

      def self.register(directive, cake_directive)
        @cake_directives[directive.downcase] = cake_directive
      end

      def self.parse_cake_directive_from(line)
        return nil unless Directives::DIRECTIVE_LINE.match?(line)

        parsed_from_line = Directives::DIRECTIVE_LINE.match(line.chomp).
                           named_captures
        directive = Directives.
                    for_cake_directive(parsed_from_line.fetch("directive")).
                    new(parsed_from_line.fetch("context"))
        directive
      end
    end
  end
end
