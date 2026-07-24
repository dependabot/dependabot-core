# typed: strong
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Powershell
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/declaration_locator"
      require_relative "file_updater/declaration_rewriter"

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        dependency_files.filter_map do |file|
          next unless file_changed?(file)

          new_content = DeclarationRewriter.new(file: file, dependencies: dependencies).updated_content
          next if new_content == file.content

          updated_file(file: file, content: new_content)
        end
      end

      private

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No PowerShell script or module manifest files found!"
      end
    end
  end
end

Dependabot::FileUpdaters.register("powershell", Dependabot::Powershell::FileUpdater)
