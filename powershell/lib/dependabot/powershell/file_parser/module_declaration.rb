# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/powershell/file_parser"

module Dependabot
  module Powershell
    class FileParser < Dependabot::FileParsers::Base
      # Represents a single PowerShell module dependency, parsed from either a
      # `#Requires -Modules` directive (in a `.ps1`/`.psm1` file) or a
      # `RequiredModules` entry (in a `.psd1` module manifest).
      class ModuleDeclaration
        extend T::Sig

        # Metadata values used to preserve the original declaration context
        # (e.g. `declaration_type`, `style`, `guid`, `version_key`) for later
        # use by the file updater when rewriting version constraints.
        MetadataValue = T.type_alias { T.nilable(T.any(String, Symbol)) }

        sig { returns(String) }
        attr_reader :name

        sig { returns(T.nilable(String)) }
        attr_reader :version

        sig { returns(T.nilable(String)) }
        attr_reader :requirement

        sig { returns(T::Hash[Symbol, MetadataValue]) }
        attr_reader :metadata

        sig do
          params(
            name: String,
            version: T.nilable(String),
            requirement: T.nilable(String),
            metadata: T::Hash[Symbol, MetadataValue]
          ).void
        end
        def initialize(name:, version: nil, requirement: nil, metadata: {})
          @name = name
          @version = version
          @requirement = requirement
          @metadata = metadata
        end
      end
    end
  end
end
