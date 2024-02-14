# typed: true
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module DummyPackageManager
  class FileUpdater < Dependabot::FileUpdaters::Base
    def updated_dependency_files
      updated_files = []
      dependency_files.each do |file|
        next unless requirement_changed?(file, dependency)

        updated_files << updated_file(file: file, content: updated_file_content(file))
      end

      updated_files.reject! { |f| dependency_files.include?(f) }
      raise "No files changed!" if updated_files.none?

      updated_files
    end

    private

    def dependency
      # Dockerfiles will only ever be updating a single dependency
      dependencies.first
    end

    def check_required_files
      # Just check if there are any files at all.
      return if dependency_files.any?

      raise "No dependency files!"
    end

    def updated_file_content(file)
      updated_content = file.content.gsub(
        /#{dependency.name} = #{previous_requirements(file).first[:requirement]}/,
        "#{dependency.name} = #{requirements(file).first[:requirement]}"
      )

      raise "Expected content to change!" if updated_content == file.content

      updated_content
    end

    def requirements(file)
      dependency.requirements
                .select { |r| r[:file] == file.name }
    end

    def previous_requirements(file)
      dependency.previous_requirements
                .select { |r| r[:file] == file.name }
    end
  end
end

Dependabot::FileUpdaters.register("dummy", DummyPackageManager::FileUpdater)
