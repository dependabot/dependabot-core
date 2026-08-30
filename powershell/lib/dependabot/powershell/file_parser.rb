# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/powershell/package_manager"

module Dependabot
  module Powershell
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      require_relative "file_parser/module_declaration"
      require_relative "file_parser/module_specification_parser"
      require_relative "file_parser/requires_directive_parser"
      require_relative "file_parser/using_module_parser"
      require_relative "file_parser/psd1_manifest_parser"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        dependency_files.each do |file|
          declarations_for_file(file).each do |declaration|
            dependency_set << build_dependency(file, declaration)
          end
        end

        dependency_set.dependencies
      end

      sig { override.returns(Dependabot::Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Dependabot::Ecosystem.new(
            name: PackageManager::NAME,
            package_manager: PackageManager.new
          ),
          T.nilable(Dependabot::Ecosystem)
        )
      end

      private

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[ModuleDeclaration]) }
      def declarations_for_file(file)
        case File.extname(file.name).downcase
        when ".psd1"
          Psd1ManifestParser.new(file: file).parse
        when ".ps1", ".psm1"
          RequiresDirectiveParser.new(file: file).parse + UsingModuleParser.new(file: file).parse
        else
          []
        end
      end

      sig { params(file: Dependabot::DependencyFile, declaration: ModuleDeclaration).returns(Dependabot::Dependency) }
      def build_dependency(file, declaration)
        Dependency.new(
          name: declaration.name,
          version: declaration.version,
          requirements: [{
            requirement: declaration.requirement,
            groups: [],
            source: nil,
            file: file.name,
            metadata: declaration.metadata
          }],
          package_manager: "powershell"
        )
      end

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No PowerShell script or module manifest files found!"
      end
    end
  end
end

Dependabot::FileParsers.register("powershell", Dependabot::Powershell::FileParser)
