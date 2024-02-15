# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module GitSubmodules
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        []
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        [updated_file(file: submodule, content: T.must(dependency.version))]
      end

      private

      sig { returns(Dependabot::Dependency) }
      def dependency
        # Git submodules will only ever be updating a single dependency
        T.must(dependencies.first)
      end

      sig { override.void }
      def check_required_files
        %w(.gitmodules).each do |filename|
          raise "No #{filename}!" unless get_original_file(filename)
        end
      end

      sig { returns(Dependabot::DependencyFile) }
      def submodule
        @submodule ||=
          T.let(
            T.must(
              dependency_files.find do |file|
                file.name == dependency.name
              end
            ),
            T.nilable(Dependabot::DependencyFile)
          )
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("submodules", Dependabot::GitSubmodules::FileUpdater)
