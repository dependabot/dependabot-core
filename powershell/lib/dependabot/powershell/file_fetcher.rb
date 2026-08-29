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
      REQUIRES_MODULES_LINE = /^[ \t]*#Requires\s+-Modules\b/i
      USING_MODULE_STATEMENT = /(?:\A|[\n;])[ \t]*using(?:[ \t]*`\r?\n[ \t]*|[ \t]+)module\b/i

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
            "PowerShell support is currently in beta. Pass `--enable-beta-ecosystems` (dry-run) or " \
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
          candidate_file_names.fetch(0).map { |name| fetch_file_from_host(name) },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def script_files_with_module_declarations
        @script_files_with_module_declarations ||= T.let(
          candidate_file_names.fetch(1)
            .map { |name| fetch_file_from_host(name) }
            .select { |f| module_declarations?(f) },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[T::Array[String]]) }
      def candidate_file_names
        @candidate_file_names ||= T.let(
          begin
            manifest_names = T.let([], T::Array[String])
            script_names = T.let([], T::Array[String])

            repo_contents(raise_errors: false).each do |entry|
              next unless entry.type == "file"

              extension = File.extname(entry.name).downcase
              if extension == MANIFEST_EXTENSION
                manifest_names << entry.name
              elsif SCRIPT_EXTENSIONS.include?(extension)
                script_names << entry.name
              end
            end

            [manifest_names, script_names]
          end,
          T.nilable(T::Array[T::Array[String]])
        )
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def module_declarations?(file)
        content = file.content
        return false unless content

        masked_content = ContentMasker.mask(content)
        return true if masked_content.match?(REQUIRES_MODULES_LINE)

        ContentMasker.mask_quoted_strings(masked_content).match?(USING_MODULE_STATEMENT)
      end
    end
  end
end

Dependabot::FileFetchers.register("powershell", Dependabot::Powershell::FileFetcher)
