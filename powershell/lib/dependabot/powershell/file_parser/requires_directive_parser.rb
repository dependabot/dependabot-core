# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/powershell/file_parser"

module Dependabot
  module Powershell
    class FileParser < Dependabot::FileParsers::Base
      # Parses `#Requires -Modules` directive lines from a PowerShell script
      # (`.ps1`) or script module (`.psm1`) file into ModuleDeclaration
      # objects.
      #
      # https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_requires
      class RequiresDirectiveParser
        extend T::Sig

        REQUIRES_MODULES_LINE = /^\s*#Requires\s+-Modules\s+(?<modules>.+)$/i

        sig { params(file: Dependabot::DependencyFile).void }
        def initialize(file:)
          @file = file
        end

        sig { returns(T::Array[ModuleDeclaration]) }
        def parse
          content = T.must(@file.content)

          content.each_line.flat_map do |line|
            match = REQUIRES_MODULES_LINE.match(line)
            next [] unless match

            ModuleSpecificationParser
              .split_entries(T.must(match[:modules]))
              .filter_map { |entry| ModuleSpecificationParser.parse(entry, declaration_type: :requires_directive) }
          end
        end
      end
    end
  end
end
