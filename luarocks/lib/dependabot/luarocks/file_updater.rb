# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/luarocks/requirement"
require "dependabot/luarocks/version"

module Dependabot
  module Luarocks
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        rockspec_files.each do |file|
          next unless file_changed?(file)

          updated_files << updated_file(
            file: file,
            content: updated_rockspec_content(file)
          )
        end

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        return if rockspec_files.any?

        raise Dependabot::DependencyFileNotFound, "No .rockspec files found."
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def rockspec_files
        dependency_files.select { |file| file.name.end_with?(".rockspec") }
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_rockspec_content(file)
        dependencies.inject(T.must(file.content)) do |content, dependency|
          update_dependency_requirement(content, dependency, file.name)
        end
      end

      sig do
        params(content: String, dependency: Dependabot::Dependency, filename: String)
          .returns(String)
      end
      def update_dependency_requirement(content, dependency, filename)
        updated_req = dependency.requirements.find { |req| req[:file] == filename }
        return content unless updated_req

        replace_dependency_line(
          content,
          dependency.name,
          updated_req[:requirement]
        )
      end

      sig { params(content: String, dependency_name: String, requirement: T.nilable(String)).returns(String) }
      def replace_dependency_line(content, dependency_name, requirement)
        pattern = /["']#{Regexp.escape(dependency_name)}[^"'\n]*["']/
        return content unless content.match?(pattern)

        content.sub(pattern) do |match|
          quote = match.start_with?("'") ? "'" : '"'
          if requirement && !requirement.empty?
            "#{quote}#{dependency_name} #{requirement}#{quote}"
          else
            "#{quote}#{dependency_name}#{quote}"
          end
        end
      end
    end
  end
end

Dependabot::FileUpdaters.register("luarocks", Dependabot::Luarocks::FileUpdater)
