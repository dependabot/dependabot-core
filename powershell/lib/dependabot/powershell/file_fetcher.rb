# typed: strong
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/powershell/content_masker"

module Dependabot
  module Powershell
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      MANIFEST_EXTENSION = ".psd1"
      SCRIPT_EXTENSIONS = T.let(%w(.ps1 .psm1).freeze, T::Array[String])
      MODULE_DECLARATION_LINE = /^(?:[ \t]*#Requires\s+-Modules\b|[ \t]*using\s+module\b)/i

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a PowerShell module manifest (.psd1) file, or a .ps1/.psm1 script " \
          "with a '#Requires -Modules' directive or 'using module' statement."
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |name| manifest_file?(name) || script_file?(name) }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "Powershell support is currently in beta. Pass `--enable-beta-ecosystems` (dry-run) or " \
            "otherwise enable the `enable_beta_ecosystems` experiment to use it."
          )
        end

        fetched_files = manifest_files + script_files_with_module_declarations

        return fetched_files if fetched_files.any?

        raise Dependabot::DependencyFileNotFound.new(nil, self.class.required_files_message)
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, Object])) }
      def ecosystem_versions
        nil
      end

      sig { params(name: String).returns(T::Boolean) }
      def self.manifest_file?(name)
        # `String#casecmp` is typed as returning a nilable Integer (nil for
        # encoding-incompatible strings), so `.zero?` on its result fails
        # Sorbet even though both operands here are always ASCII extension
        # literals. Compare directly instead.
        # rubocop:disable Performance/Casecmp
        File.extname(name).downcase == MANIFEST_EXTENSION.downcase
        # rubocop:enable Performance/Casecmp
      end

      sig { params(name: String).returns(T::Boolean) }
      def self.script_file?(name)
        SCRIPT_EXTENSIONS.include?(File.extname(name).downcase)
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def manifest_files
        @manifest_files ||= T.let(
          repo_contents(raise_errors: false)
            .select { |f| f.type == "file" && self.class.manifest_file?(f.name) }
            .map { |f| fetch_file_from_host(f.name) },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def script_files_with_module_declarations
        @script_files_with_module_declarations ||= T.let(
          repo_contents(raise_errors: false)
            .select { |f| f.type == "file" && self.class.script_file?(f.name) }
            .map { |f| fetch_file_from_host(f.name) }
            .select { |f| module_declarations?(f) },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def module_declarations?(file)
        content = file.content
        return false unless content

        ContentMasker.mask(content).match?(MODULE_DECLARATION_LINE)
      end
    end
  end
end

Dependabot::FileFetchers.register("powershell", Dependabot::Powershell::FileFetcher)
