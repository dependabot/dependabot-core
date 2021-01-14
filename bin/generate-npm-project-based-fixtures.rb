#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "byebug"
require "open3"

# Generate project based fixtures for npm and yarn
class ProjectBasedFixtureGenerator
  def run
    FileUtils.mkdir_p(npm6_project_dir)
    FileUtils.mkdir_p(yarn_project_dir)
    _, _, status = Open3.capture3("npm install --global npm@6")
    abort("failed to install npm@6 globally") unless status.success?

    _, _, status = Open3.capture3("yarn upgrade v1.22.5")
    abort("failed to install yarn v1.22.5") unless status.success?

    npm_package_files.each do |filename|
      build_npm_project(filename)
      build_yarn_project(filename)
    end
  end

  private

  def build_npm_project(filename)
    project_name = File.basename(filename, ".json")
    project_dir = FileUtils.mkdir_p(File.join(npm6_project_dir, project_name)).last
    FileUtils.copy(filename, File.join(project_dir, "package.json"))
    Dir.chdir(project_dir) do
      _, _, status = Open3.capture3("npm install")
      unless status.success?
        puts "Failed to generate an npm lockfile for: #{project_dir}. The manifest file might "\
          "be broken on purpose, you may need to manually include a lockfile when using this project"
      end

      FileUtils.remove_dir("node_modules") if Dir.exist?("node_modules")
    end
  end

  def build_yarn_project(filename)
    project_name = File.basename(filename, ".json")
    project_dir = FileUtils.mkdir_p(File.join(yarn_project_dir, project_name)).last
    FileUtils.copy(filename, File.join(project_dir, "package.json"))
    Dir.chdir(project_dir) do
      _, _, status = Open3.capture3("yarn install")
      unless status.success?
        puts "Failed to generate a yarn lockfile for: #{project_dir}. The manifest file might "\
          "be broken on purpose, you may need to manually include a lockfile when using this project"
      end

      FileUtils.remove_dir("node_modules") if Dir.exist?("node_modules")
    end
  end

  def npm6_project_dir
    "npm_and_yarn/spec/fixtures/projects/npm6"
  end

  def yarn_project_dir
    "npm_and_yarn/spec/fixtures/projects/yarn"
  end

  def npm_package_files
    Dir.glob("npm_and_yarn/spec/fixtures/package_files/*.json")
  end
end

ProjectBasedFixtureGenerator.new.run
