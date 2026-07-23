# typed: strict
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Powershell
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      MANIFEST_EXTENSION = ".psd1"
      SCRIPT_EXTENSIONS = T.let(%w(.ps1 .psm1).freeze, T::Array[String])
      REQUIRES_MODULES_LINE = /^\s*#Requires\s+-Modules\b/i

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a PowerShell module manifest (.psd1) file, or a .ps1/.psm1 script " \
          "with a '#Requires -Modules' directive."
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
            "Powershell support is currently in beta. Set ALLOW_BETA_ECOSYSTEMS=true to enable it."
          )
        end

        fetched_files = manifest_files + script_files_with_requires

        return fetched_files if fetched_files.any?

        raise Dependabot::DependencyFileNotFound.new(nil, self.class.required_files_message)
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, Object])) }
      def ecosystem_versions
        nil
      end

      sig { params(name: String).returns(T::Boolean) }
      def self.manifest_file?(name)
        File.extname(name).casecmp(MANIFEST_EXTENSION).zero?
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
      def script_files_with_requires
        @script_files_with_requires ||= T.let(
          repo_contents(raise_errors: false)
            .select { |f| f.type == "file" && self.class.script_file?(f.name) }
            .map { |f| fetch_file_from_host(f.name) }
            .select { |f| requires_modules?(f) },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def requires_modules?(file)
        content = file.content
        return false unless content

        content.match?(REQUIRES_MODULES_LINE)
      end
    end
  end
end

Dependabot::FileFetchers.register("powershell", Dependabot::Powershell::FileFetcher)
