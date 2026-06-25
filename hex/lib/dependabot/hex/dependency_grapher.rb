# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
require "dependabot/hex/file_parser"
require "dependabot/shared_helpers"

module Dependabot
  module Hex
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      extend T::Sig

      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        lockfile || T.must(mixfile)
      end

      private

      sig { override.returns(T::Hash[String, Dependabot::DependencyGraphers::ResolvedDependency]) }
      def build_resolved_dependencies
        graph_data.each_with_object({}) do |entry, resolved|
          purl = entry["purl"]
          resolved[purl] = Dependabot::DependencyGraphers::ResolvedDependency.new(
            package_url: purl,
            direct: entry["direct"],
            runtime: entry["runtime"],
            dependencies: entry["dependencies"]
          )
        end
      end

      sig { returns(T::Array[T::Hash[String, T.untyped]]) }
      def graph_data
        @graph_data ||= T.let(fetch_graph_data, T.nilable(T::Array[T::Hash[String, T.untyped]]))
      end

      sig { returns(T::Array[T::Hash[String, T.untyped]]) }
      def fetch_graph_data
        SharedHelpers.in_a_temporary_directory do
          write_sanitized_mixfiles
          File.write("mix.lock", T.must(lockfile).content) if lockfile

          SharedHelpers.run_helper_subprocess(
            env: { "MIX_QUIET" => "1" },
            command: "dependabot_hex",
            function: "dependency_graph",
            args: [Dir.pwd],
            stderr_to_stdout: true
          )
        end
      end

      sig { void }
      def write_sanitized_mixfiles
        hex_parser = T.cast(file_parser, Dependabot::Hex::FileParser)
        hex_parser.send(:mixfiles).each do |file|
          path = file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, hex_parser.send(:sanitize_mixfile, T.must(file.content)))
        end
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(
          dependency_files.find { |f| f.name == "mix.lock" },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def mixfile
        @mixfile ||= T.let(
          dependency_files.find { |f| f.name.end_with?("mix.exs") },
          T.nilable(Dependabot::DependencyFile)
        )
      end
    end
  end
end

Dependabot::DependencyGraphers.register("hex", Dependabot::Hex::DependencyGrapher)
