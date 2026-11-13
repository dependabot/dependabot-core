# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/clojure/constants"
require "dependabot/clojure/native_helpers"

module Dependabot
  module Clojure
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = dependency_files.filter_map do |file|
          declarations = declarations_to_update(file)
          next if declarations.empty?

          updated_file(file: file, content: updated_content(file, declarations))
        end

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        return if get_original_file(LEIN_FILE_NAME) || get_original_file(DEPS_FILE_NAME)

        raise "No #{LEIN_FILE_NAME} or #{DEPS_FILE_NAME}!"
      end

      # Maps each declaration in the file that needs a new version to that version.
      sig { params(file: Dependabot::DependencyFile).returns(T::Hash[NativeHelpers::Declaration, String]) }
      def declarations_to_update(file)
        declarations = NativeHelpers.parse(file).declarations

        dependencies.each_with_object({}) do |dependency, updates|
          changed_requirements(dependency, file).each do |new_req, old_req|
            declarations.each do |declaration|
              next unless declaration.name == dependency.name
              next unless declaration.version == old_req.requirement
              next unless declaration.groups == old_req.groups

              updates[declaration] = T.must(new_req.requirement)
            end
          end
        end
      end

      sig do
        params(dependency: Dependabot::Dependency, file: Dependabot::DependencyFile)
          .returns(T::Array[[Dependabot::DependencyRequirement, Dependabot::DependencyRequirement]])
      end
      def changed_requirements(dependency, file)
        dependency.requirements.zip(dependency.previous_requirements.to_a).filter_map do |new_req, old_req|
          next unless old_req && new_req.file == file.name
          next if new_req.requirement == old_req.requirement

          [new_req, old_req]
        end
      end

      # Rewrites each version string at the position reported by the helper.
      # Edits run from the end of the file, so earlier positions stay valid.
      # Positions are checked before writing, so a mismatch fails instead of
      # corrupting the file.
      sig do
        params(
          file: Dependabot::DependencyFile,
          updates: T::Hash[NativeHelpers::Declaration, String]
        ).returns(String)
      end
      def updated_content(file, updates)
        content = T.must(file.content).dup
        line_offsets = line_start_offsets(content)

        updates.sort_by { |declaration, _| [-declaration.row, -declaration.col] }.each do |declaration, version|
          original = %("#{declaration.version}")
          mismatch = "Expected #{original} at line #{declaration.row} of #{file.name}"
          line_start = line_offsets[declaration.row - 1]
          raise mismatch unless line_start && declaration.end_row == declaration.row

          start = char_index(content, line_start, declaration.col - 1)
          length = char_index(content, line_start, declaration.end_col - 1) - start
          raise mismatch unless content[start, length] == original

          content[start, length] = %("#{version}")
        end

        content
      end

      # The helper runs on the JVM, so columns count UTF-16 code units: characters
      # outside the Basic Multilingual Plane, such as emoji, take two.
      sig { params(content: String, line_start: Integer, utf16_column: Integer).returns(Integer) }
      def char_index(content, line_start, utf16_column)
        index = line_start
        units = 0
        while units < utf16_column && index < content.length
          units += T.must(content[index]).ord > 0xFFFF ? 2 : 1
          index += 1
        end
        index
      end

      sig { params(content: String).returns(T::Array[Integer]) }
      def line_start_offsets(content)
        offsets = [0]
        content.each_line { |line| offsets << (offsets.fetch(-1) + line.length) }
        offsets
      end
    end
  end
end

Dependabot::FileUpdaters.register(Dependabot::Clojure::ECOSYSTEM, Dependabot::Clojure::FileUpdater)
