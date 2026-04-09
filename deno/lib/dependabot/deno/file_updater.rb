# typed: strict
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Deno
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      MANIFEST_FILENAMES = T.let(%w(deno.json deno.jsonc).freeze, T::Array[String])

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        dependency_files.each do |file|
          next unless MANIFEST_FILENAMES.include?(file.name)

          new_content = update_manifest_content(file)
          next if new_content == file.content

          updated_files << updated_file(file: file, content: new_content)
        end

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        return if dependency_files.any? { |f| MANIFEST_FILENAMES.include?(f.name) }

        raise "No deno.json or deno.jsonc found!"
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def update_manifest_content(file)
        content = T.must(file.content)

        dependencies.each do |dep|
          prev_reqs = dep.previous_requirements&.select { |r| r[:file] == file.name } || []
          new_reqs = dep.requirements.select { |r| r[:file] == file.name }

          prev_reqs.zip(new_reqs).each do |prev_req, new_req|
            source_type = prev_req[:source][:type]
            old_specifier = "#{source_type}:#{dep.name}@#{prev_req[:requirement]}"
            new_specifier = "#{source_type}:#{dep.name}@#{T.must(new_req)[:requirement]}"

            content = content.gsub(old_specifier, new_specifier)
          end
        end

        content
      end
    end
  end
end

Dependabot::FileUpdaters.register("deno", Dependabot::Deno::FileUpdater)
