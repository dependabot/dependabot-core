# typed: false
# frozen_string_literal: true

require "spec_helper"

$LOAD_PATH.unshift(File.join(ENV.fetch("DEPENDABOT_HOME"), "dependabot-updater", "lib"))

require "dependabot/dependency_change_builder"
require "dependabot/dependency_file"
require "dependabot/go_modules/file_updater"
require "dependabot/job"

RSpec.describe Dependabot::DependencyChangeBuilder do
  subject(:create_change) do
    described_class.create_from(
      job: job,
      dependency_files: dependency_files,
      updated_dependencies: updated_dependencies,
      change_source: change_source
    )
  end

  let(:source) { Dependabot::Source.new(provider: "github", repo: "example/workspace", directory: "/libs") }
  let(:job) do
    instance_double(
      Dependabot::Job,
      package_manager: "go_modules",
      repo_contents_path: repo_contents_path,
      credentials: [],
      experiments: {},
      security_updates_only?: false,
      cooldown: nil,
      blocked_versions: [],
      reject_external_code?: false,
      source: source
    )
  end
  let(:repo_contents_path) do
    write_tmp_repo(
      dependency_files.map do |file|
        Dependabot::DependencyFile.new(name: file.path.delete_prefix("/"), content: file.content)
      end
    )
  end
  let(:change_source) { updated_dependencies.first }
  let(:updated_dependencies) do
    [
      Dependabot::Dependency.new(
        name: "golang.org/x/sys",
        version: "0.33.0",
        previous_version: "0.32.0",
        requirements: [],
        previous_requirements: [],
        package_manager: "go_modules"
      )
    ]
  end
  let(:go_mod_content) { "module example.com/libs\n\ngo 1.21\n\nrequire golang.org/x/sys v0.32.0\n" }
  let(:updated_go_mod_content) { go_mod_content.sub("1.21", "1.23").sub("v0.32.0", "v0.33.0") }
  let(:go_sum_content) { "original module checksums\n" }
  let(:updated_go_sum_content) { "updated module checksums\n" }
  let(:go_work_content) { "go 1.21\n\nuse (\n\t./libs\n\t./services\n)\n" }
  let(:updated_go_work_content) { go_work_content.sub("1.21", "1.23") }
  let(:dependency_files) do
    {
      "go.mod" => go_mod_content,
      "go.sum" => go_sum_content,
      "../go.work" => go_work_content,
      "../go.work.sum" => "original workspace checksums\n",
      "../services/go.mod" => "module example.com/services\n\ngo 1.21\n"
    }.map do |name, content|
      Dependabot::DependencyFile.new(name: name, content: content, directory: "/libs", support_file: true)
    end
  end
  let(:updated_workspace_files) do
    {
      "../go.work" => updated_go_work_content,
      "../go.work.sum" => "updated workspace checksums\n"
    }
  end
  let(:go_mod_updater) do
    instance_double(
      Dependabot::GoModules::FileUpdater::GoModUpdater,
      updated_go_mod_content: updated_go_mod_content,
      updated_go_sum_content: updated_go_sum_content,
      updated_ancestor_workspace_files: updated_workspace_files
    )
  end

  before do
    Dependabot::Experiments.register(:enable_go_work_version_sync, true)
    allow(Dependabot::GoModules::FileUpdater::GoModUpdater).to receive(:new).and_return(go_mod_updater)
  end

  after { FileUtils.rm_rf(repo_contents_path) }

  it "keeps the dependency edits and workspace changes in the final change" do
    expect(create_change.updated_dependency_files).to contain_exactly(
      have_attributes(path: "/libs/go.mod", content: updated_go_mod_content, support_file: false),
      have_attributes(path: "/libs/go.sum", content: updated_go_sum_content, support_file: false),
      have_attributes(path: "/go.work", content: updated_go_work_content, support_file: false),
      have_attributes(path: "/go.work.sum", content: "updated workspace checksums\n", support_file: false)
    )
  end

  it "leaves the input files and contextual sibling manifest untouched" do
    original_files = dependency_files.map(&:to_h)

    create_change

    expect(dependency_files.map(&:to_h)).to eq(original_files)
  end

  context "when the change belongs to a dependency group" do
    let(:change_source) { Dependabot::DependencyGroup.new(name: "go", rules: { patterns: ["*"] }) }

    it "keeps the complete grouped update" do
      change = create_change

      expect(change).to be_grouped_update
      expect(change.updated_dependency_files.map(&:path))
        .to contain_exactly("/libs/go.mod", "/libs/go.sum", "/go.work", "/go.work.sum")
    end
  end

  context "when the member checksums are unchanged" do
    let(:updated_go_sum_content) { go_sum_content }

    it "does not include the unchanged member file" do
      expect(create_change.updated_dependency_files.map(&:path))
        .to contain_exactly("/libs/go.mod", "/go.work", "/go.work.sum")
    end
  end

  context "when only the workspace checksums change" do
    let(:updated_go_work_content) { go_work_content }

    it "keeps the member edits alongside the workspace checksums" do
      expect(create_change.updated_dependency_files.map(&:path))
        .to contain_exactly("/libs/go.mod", "/libs/go.sum", "/go.work.sum")
    end
  end

  context "when neither ancestor workspace file changes" do
    let(:updated_workspace_files) do
      {
        "../go.work" => go_work_content,
        "../go.work.sum" => "original workspace checksums\n"
      }
    end

    it "preserves the support-only update without promoting contextual files" do
      expect(create_change.updated_dependency_files).to contain_exactly(
        have_attributes(path: "/libs/go.mod", content: updated_go_mod_content, support_file: true),
        have_attributes(path: "/libs/go.sum", content: updated_go_sum_content, support_file: true)
      )
    end
  end
end
