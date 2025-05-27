# typed: strict
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/julia/version"
require "toml-rb"

module Dependabot
  module Julia
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      sig { override.returns(T.nilable(Dependabot::Julia::Version)) }
      def latest_version
        latest_resolvable_version # Pass nil or appropriate args if base class expects them
      end

      sig { override.params(ignored: T.untyped).returns(T.nilable(Dependabot::Julia::Version)) }
      def latest_resolvable_version(ignored = nil)
        SharedHelpers.in_a_temporary_directory do |dir|
          # Copy project files into the temporary directory
          dependency_files.each do |file|
            path = File.join(dir, file.name)
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, file.content)
          end

          # Run Julia package manager to update the dependency
          SharedHelpers.run_shell_command(
            "julia --project=#{dir} -e 'import Pkg; Pkg.update(\"#{dependency.name}\")'",
            allow_unsafe_shell_command: true
          )

          # Read the version from the updated manifest file
          read_version(dir.to_s, dependency.name)
        end
      end

      sig { params(dir: String, name: String).returns(T.nilable(Dependabot::Julia::Version)) }
      def read_version(dir, name)
        mf = TomlRB.parse(File.read(File.join(dir, "Manifest.toml")))
        stanza = mf[name]&.find { |s| s["version"] }
        return nil unless stanza
        return nil unless stanza["version"]

        Version.new(stanza["version"])
      end

      sig { params(file: DependencyFile).returns(T::Hash[String, T.untyped]) }
      def parse_manifest(file)
        old = manifest_file ? TomlRB.parse(T.must(manifest_file).content) : {}
        begin
          old
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          raise Dependabot::DependencyFileNotParseable, file.path
        end
      end

      sig { returns(T.nilable(DependencyFile)) }
      def manifest_file
        dependency_files.find { |f| f.name.match?(/Manifest(?:-v[\d.]+)?\.toml$/i) }
      end
    end
  end
end

Dependabot::UpdateCheckers.register("julia", Dependabot::Julia::UpdateChecker)
