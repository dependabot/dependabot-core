# typed: strict

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/nuget/native_discovery/native_discovery_json_reader"
require "dependabot/nuget/native_helpers"
require "dependabot/nuget/package_manager"
require "dependabot/nuget/language"
require "sorbet-runtime"

# For details on how dotnet handles version constraints, see:
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning
module Dependabot
  module Nuget
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependencies
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: language
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { returns(T::Array[Dependabot::Dependency]) }
      def content_json
        @content_json ||= T.let(begin
          directory = source&.directory || "/"
          discovery_json_reader = Dependabot::Nuget::NativeDiscovery::NativeDiscoveryJsonReader.run_discovery_in_directory(
            repo_contents_path: T.must(repo_contents_path),
            directory: directory,
            credentials: credentials
          )
          discovery_json_reader.dependency_set.dependencies
        end, T.nilable(T::Array[Dependabot::Dependency]))
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      def dependencies
        @dependencies ||= T.let(begin
          directory = source&.directory || "/"
          discovery_json_reader = NativeDiscoveryJsonReader.run_discovery_in_directory(
            repo_contents_path: T.must(repo_contents_path),
            directory: directory,
            credentials: credentials
          )
          discovery_json_reader.dependency_set.dependencies
        end, T.nilable(T::Array[Dependabot::Dependency]))
      end

      sig { override.void }
      def check_required_files
        requirement_files = dependencies.flat_map do |dep|
          dep.requirements.map { |r| T.let(r.fetch(:file), String) }
        end.uniq

        project_files = requirement_files.select { |f| File.basename(f).match?(/\.(cs|vb|fs)proj$/) }
        global_json_file = requirement_files.select { |f| File.basename(f) == "global.json" }
        dotnet_tools_json_file = requirement_files.select { |f| File.basename(f) == "dotnet-tools.json" }
        return if project_files.any? || global_json_file.any? || dotnet_tools_json_file.any?

        raise Dependabot::DependencyFileNotFound.new(
          "*.(cs|vb|fs)proj",
          "No project file."
        )
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def language
        # Historically new version of language is released with incremental update of
        # .Net version, so we tie the language with framework version for metric collection

        nomenclature = "#{language_type} #{framework_version&.first}".strip.tr(" ", "-")

        Dependabot.logger.info("Detected language and framework #{nomenclature}")

        case language_type

        when CSharpLanguage::TYPE
          CSharpLanguage.new(nomenclature)

        when VBLanguage::TYPE
          VBLanguage.new(nomenclature)

        when FSharpLanguage::TYPE
          FSharpLanguage.new(nomenclature)

        when DotNet::TYPE
          DotNet.new(nomenclature)

        end
      end

      sig { returns(T.nilable(T::Array[T.nilable(String)])) }
      def framework_version
        # pending due to some issue with sorbet during CI tests
        []
      rescue StandardError
        nil
      end

      sig { returns(T.nilable(String)) }
      def language_type
        requirement_files = dependencies.flat_map do |dep|
          dep.requirements.map { |r| T.let(r.fetch(:file), String) }
        end.uniq

        return "cs" if requirement_files.any? { |f| File.basename(f).match?(/\.csproj$/) }
        return "vb" if requirement_files.any? { |f| File.basename(f).match?(/\.vbproj$/) }
        return "fs" if requirement_files.any? { |f| File.basename(f).match?(/\.fsproj$/) }

        # return a fallback to avoid falling to exception
        "dotnet"
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        NugetPackageManager.new(nuget_version)
      end

      sig { returns(T.nilable(String)) }
      def nuget_version
        SharedHelpers.run_shell_command("dotnet nuget --version").split("Command Line").last&.strip
      rescue StandardError
        nil
      end
    end
  end
end

Dependabot::FileParsers.register("nuget", Dependabot::Nuget::FileParser)
