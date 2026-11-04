# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/go_modules/file_updater"

RSpec.describe Dependabot::GoModules::FileUpdater do
  let(:repo_contents_path) { build_tmp_repo(project_name) }
  let(:work_override) { false }
  let(:credentials) { [] }
  let(:dependency_name) { project_name == "workspace" ? "github.com/fatih/color" : "rsc.io/quote" }
  let(:previous_version) { project_name == "workspace" ? "v1.7.0" : "v1.5.1" }
  let(:version) { project_name == "workspace" ? "v1.16.0" : "v1.5.2" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      previous_version: previous_version,
      requirements: [],
      previous_requirements: [],
      package_manager: "go_modules"
    )
  end
  let(:files) do
    project_dependency_files(project_name).filter_map do |file|
      next unless file.name.match?(/go\.(mod|sum|work|work\.sum)$/)

      content = file.content
      content = content.gsub("rsc.io/quote v1.5.2", "rsc.io/quote v1.5.1") if project_name == "workspace_no_root_mod"
      if file.name.end_with?("go.mod")
        target = Pathname.new("../external").relative_path_from(Pathname.new(File.dirname(file.name)))
        content += "\nrequire example.com/shared v0.0.0\n"
        content += "// Keep #{target} for local development.\n"
        content += "replace example.com/shared v0.0.0 => #{target}\n"
      elsif file.name == "go.work" && work_override
        content += "\nreplace example.com/shared => ../override\n"
      end
      Dependabot::DependencyFile.new(name: file.name, content: content, directory: "/")
    end
  end
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials,
      repo_contents_path: repo_contents_path
    )
  end

  def expect_original_replacements
    files.select { |file| file.name.end_with?("go.mod", "go.work") }.each do |file|
      content = File.read(File.join(repo_contents_path, file.name))
      file.content.lines.grep(%r{^(replace|// Keep)}).each do |line|
        expect(content).to include(line.strip)
      end
      expect(content).not_to include("dependabot-replacements-")
    end
  end

  %w(workspace workspace_no_root_mod).each do |project|
    context "with #{project}" do
      let(:project_name) { project }

      it "updates every member requiring the public dependency and restores local bindings" do
        updated = updater.updated_dependency_files
        expected_names = files.select { |file| file.name.end_with?("go.mod") }.map(&:name)
        modules = updated.select { |file| file.name.end_with?("go.mod") }

        expect(modules.map(&:name)).to match_array(expected_names)
        modules.each do |file|
          expect(file.content).to include("#{dependency_name} #{version}")
          expect(file.content).not_to include("dependabot-replacements-")
        end
        expect_original_replacements
      end

      context "with a workfile replacement override" do
        let(:work_override) { true }

        it "updates members while preserving the workfile override" do
          expect(updater.updated_dependency_files).not_to be_empty
          expect_original_replacements
        end
      end

      it "restores all bindings when go get fails" do
        allow(Open3).to receive(:capture3).and_call_original
        error = "controlled go get failure"
        allow(Open3).to receive(:capture3).with(a_string_starting_with("go get")).and_raise(error)

        expect { updater.updated_dependency_files }.to raise_error(RuntimeError, "controlled go get failure")
        expect_original_replacements
      end
    end
  end
end
