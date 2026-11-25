# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/create_group_update_pull_request"

RSpec.describe Dependabot::Updater::Operations::CreateGroupUpdatePullRequest do
  subject(:updated_files) do
    T.must(operation.compile_all_dependency_changes_for_directories(group)).updated_dependency_files
  end

  let(:operation) do
    described_class.new(
      service: instance_double(Dependabot::Service),
      job: instance_double(Dependabot::Job, source: source),
      dependency_snapshot: snapshot,
      error_handler: instance_double(Dependabot::Updater::ErrorHandler),
      group: group
    )
  end
  let(:group) { instance_double(Dependabot::DependencyGroup) }
  let(:directories) { %w(/project /other /third /last).first(file_changes.length) }
  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "example/project", directories: directories)
  end
  let(:manifest_files) do
    directories.map do |directory|
      Dependabot::DependencyFile.new(name: "go.mod", content: "module example/project", directory: directory)
    end
  end
  let(:snapshot) do
    instance_double(Dependabot::DependencySnapshot, all_dependency_files: manifest_files)
  end
  let(:vendor_file) do
    Dependabot::DependencyFile.new(
      name: "vendor/example.com/module/file.go",
      content: "updated",
      directory: "/project",
      vendored_file: true
    )
  end
  let(:created_file) do
    vendor_file.dup.tap { |file| file.operation = Dependabot::DependencyFile::Operation::CREATE }
  end
  let(:deleted_file) do
    Dependabot::DependencyFile.new(
      name: vendor_file.name,
      content: nil,
      directory: vendor_file.directory,
      vendored_file: true,
      deleted: true
    )
  end
  let(:file_changes) { [[vendor_file]] }
  let(:directory_changes) do
    file_changes.map do |files|
      instance_double(
        Dependabot::DependencyChange,
        updated_dependencies: [],
        updated_dependency_files: files,
        merge_changes!: nil
      )
    end
  end

  before do
    allow(snapshot).to receive(:current_directory=)
    allow(snapshot).to receive(:dependency_files) do
      manifest_files.select { |file| file.directory == source.directory }
    end
    allow(operation).to receive(:compile_all_dependency_changes_for).and_return(*directory_changes)
  end

  it "preserves update for an existing vendored file absent from the fetched manifests" do
    expect(updated_files).to contain_exactly(
      have_attributes(name: vendor_file.name, operation: Dependabot::DependencyFile::Operation::UPDATE)
    )
  end

  context "when an existing vendored file is deleted" do
    let(:file_changes) { [[deleted_file]] }

    it "preserves the deletion" do
      expect(updated_files).to contain_exactly(
        have_attributes(name: vendor_file.name, operation: Dependabot::DependencyFile::Operation::DELETE)
      )
    end
  end

  context "when an existing vendored file is deleted and recreated across directories" do
    let(:file_changes) { [[deleted_file], [created_file]] }

    it "reports the recreated file as an update" do
      expect(updated_files).to contain_exactly(
        have_attributes(name: vendor_file.name, operation: Dependabot::DependencyFile::Operation::UPDATE)
      )
    end
  end

  context "when a new vendored file is changed in a later directory" do
    let(:file_changes) { [[created_file], [vendor_file]] }

    it "keeps the file as a create" do
      expect(updated_files).to contain_exactly(
        have_attributes(name: vendor_file.name, operation: Dependabot::DependencyFile::Operation::CREATE)
      )
    end
  end

  context "when a new vendored file is created and deleted across directories" do
    let(:file_changes) { [[created_file], [deleted_file]] }

    it "omits the transient file" do
      expect(updated_files).to be_empty
    end
  end

  context "when a new vendored file is deleted repeatedly and recreated across directories" do
    let(:file_changes) { [[created_file], [deleted_file], [deleted_file], [created_file]] }

    it "retains its initial absence" do
      expect(updated_files).to contain_exactly(
        have_attributes(name: vendor_file.name, operation: Dependabot::DependencyFile::Operation::CREATE)
      )
    end
  end
end
