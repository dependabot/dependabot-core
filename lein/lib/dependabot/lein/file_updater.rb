# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Lein
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        [/^project\.clj$/]
      end

      def updated_dependency_files
        file = dependency_files.find { |f| f.name == "project.clj" }.dup

        dependencies.each do |dependency|
          file = update_project(
            file: file,
            dependency: dependency
          )
        end

        [file]
      end

      private

      def update_project(file:, dependency:)
        content = file.content
        name = dependency.name.split(":").uniq.join("/")
        pv = dependency.previous_version
        cv = dependency.version

        # TODO: Handle "shortcutted" names explicitly
        # This works, but if a project.clj has for example utils/utils and
        # other-utils/utils there would be issues!
        content = content.gsub("#{name} \"#{pv}\"", "#{name} \"#{cv}\"")

        updated_file(file: file, content: content)
      end

      def check_required_files
        raise "No project.clj!" unless get_original_file("project.clj")
      end
    end
  end
end

Dependabot::FileUpdaters.register("lein", Dependabot::Lein::FileUpdater)
