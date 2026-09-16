# typed: strict
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/job"
require "dependabot/source"
require "dependabot/updater/operations"

require "spec_helper"

RSpec.describe Dependabot::Updater::DependencyGroupChangeBatch do
  extend T::Sig

  describe "#merge" do
    let(:initial_file) do
      Dependabot::DependencyFile.new(name: "Gemfile.lock", content: "initial", directory: "/")
    end
    let(:updated_file) do
      Dependabot::DependencyFile.new(name: "Gemfile.lock", content: "first update", directory: "/")
    end
    let(:second_update) do
      Dependabot::DependencyFile.new(name: "Gemfile.lock", content: "second update", directory: "/")
    end
    let(:vendored_file) do
      Dependabot::DependencyFile.new(
        name: "vendor/cache/example.gem",
        content: "vendored",
        directory: "/",
        vendored_file: true
      )
    end
    let(:batch) { described_class.new(initial_dependency_files: [initial_file]) }
    let(:logger) { instance_double(Logger, debug?: true, debug: nil) }

    before do
      allow(Dependabot).to receive(:logger).and_return(logger)
    end

    it "tracks changed and vendored files" do
      change = instance_double(
        Dependabot::DependencyChange,
        updated_dependencies: [],
        updated_dependency_files: [updated_file, vendored_file],
        notices: []
      )

      batch.merge(change)

      expect(batch.updated_dependency_files).to contain_exactly(updated_file, vendored_file)
    end

    it "increments repeated changes and retains the newest file" do
      first_change = instance_double(
        Dependabot::DependencyChange,
        updated_dependencies: [],
        updated_dependency_files: [updated_file],
        notices: []
      )
      second_change = instance_double(
        Dependabot::DependencyChange,
        updated_dependencies: [],
        updated_dependency_files: [second_update],
        notices: []
      )

      batch.merge(first_change)
      expect(logger).to receive(:debug).with("  - /Gemfile.lock ( Changed 2 times )")
      batch.merge(second_change)

      expect(batch.updated_dependency_files).to eq([second_update])
    end

    it "retains create when a new vendored file changes again" do
      created_file = Dependabot::DependencyFile.new(
        name: "vendor/cache/new.gem",
        content: "created",
        directory: "/",
        vendored_file: true,
        operation: Dependabot::DependencyFile::Operation::CREATE
      )
      changed_file = Dependabot::DependencyFile.new(
        name: "vendor/cache/new.gem",
        content: "changed",
        directory: "/",
        vendored_file: true,
        operation: Dependabot::DependencyFile::Operation::UPDATE
      )

      batch.merge(dependency_change_for(created_file))
      batch.merge(dependency_change_for(changed_file))

      expect(batch.updated_dependency_files).to contain_exactly(
        have_attributes(content: "changed", operation: Dependabot::DependencyFile::Operation::CREATE)
      )
    end

    it "uses update when an existing vendored file is deleted and recreated" do
      changed_file = Dependabot::DependencyFile.new(
        name: "vendor/cache/existing.gem",
        content: "changed",
        directory: "/",
        vendored_file: true,
        operation: Dependabot::DependencyFile::Operation::UPDATE
      )
      deleted_file = Dependabot::DependencyFile.new(
        name: "vendor/cache/existing.gem",
        content: nil,
        directory: "/",
        vendored_file: true,
        deleted: true
      )
      recreated_file = Dependabot::DependencyFile.new(
        name: "vendor/cache/existing.gem",
        content: "recreated",
        directory: "/",
        vendored_file: true,
        operation: Dependabot::DependencyFile::Operation::CREATE
      )

      batch.merge(dependency_change_for(changed_file))
      batch.merge(dependency_change_for(deleted_file))
      batch.merge(dependency_change_for(recreated_file))

      expect(batch.updated_dependency_files).to contain_exactly(
        have_attributes(content: "recreated", operation: Dependabot::DependencyFile::Operation::UPDATE)
      )
    end

    it "uses update when an initial non-vendored file is deleted and recreated" do
      deleted_file = Dependabot::DependencyFile.new(
        name: initial_file.name,
        content: nil,
        directory: initial_file.directory,
        deleted: true
      )
      recreated_file = Dependabot::DependencyFile.new(
        name: initial_file.name,
        content: "recreated",
        directory: initial_file.directory,
        operation: Dependabot::DependencyFile::Operation::CREATE
      )

      batch.merge(dependency_change_for(deleted_file))
      batch.merge(dependency_change_for(recreated_file))

      expect(batch.updated_dependency_files).to contain_exactly(
        have_attributes(content: "recreated", operation: Dependabot::DependencyFile::Operation::UPDATE)
      )
    end

    it "drops a new vendored file that is deleted before the group is complete" do
      created_file = Dependabot::DependencyFile.new(
        name: "vendor/cache/transient.gem",
        content: "created",
        directory: "/",
        vendored_file: true,
        operation: Dependabot::DependencyFile::Operation::CREATE
      )
      deleted_file = Dependabot::DependencyFile.new(
        name: "vendor/cache/transient.gem",
        content: nil,
        directory: "/",
        vendored_file: true,
        deleted: true
      )

      batch.merge(dependency_change_for(created_file))
      batch.merge(dependency_change_for(deleted_file))

      expect(batch.updated_dependency_files).to be_empty
    end

    it "deduplicates notices from dependency changes" do
      notice = Dependabot::Notice.new(
        mode: Dependabot::Notice::NoticeMode::WARN,
        type: "cooldown_date_unavailable",
        package_manager_name: "bundler",
        description: "Cooldown was not applied.",
        show_in_pr: true,
        show_alert: false
      )
      change = instance_double(
        Dependabot::DependencyChange,
        updated_dependencies: [],
        updated_dependency_files: [],
        notices: [notice]
      )

      batch.merge(change)
      batch.merge(change)

      expect(batch.notices).to contain_exactly(notice)
    end
  end

  sig do
    params(files: Dependabot::DependencyFile)
      .returns(Dependabot::DependencyChange)
  end
  def dependency_change_for(*files)
    T.cast(
      instance_double(
        Dependabot::DependencyChange,
        updated_dependencies: [],
        updated_dependency_files: files,
        notices: []
      ),
      Dependabot::DependencyChange
    )
  end

  describe "current_dependency_files" do
    let(:files) do
      [
        Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-gemfile", directory: "/"),
        Dependabot::DependencyFile.new(name: "Gemfile.lock", content: "mock-gemfile-lock", directory: "/hello/.."),
        Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-package-json", directory: "/elsewhere"),
        Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-package-json", directory: "unknown"),
        Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-package-json", directory: "../../oob")
      ]
    end

    let(:job) do
      instance_double(Dependabot::Job, source: source, package_manager: package_manager)
    end

    let(:package_manager) { "bundler" }

    let(:source) do
      Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: directory)
    end

    let(:directory) { "/" }

    it "returns the current dependency files filtered by directory" do
      expect(
        described_class.new(initial_dependency_files: files)
                .current_dependency_files(job).map(&:name)
      ).to eq(%w(Gemfile Gemfile.lock))
    end

    context "when the directory has a dot" do
      let(:directory) { "/." }

      it "normalizes the directory" do
        expect(
          described_class.new(initial_dependency_files: files)
                    .current_dependency_files(job).map(&:name)
        ).to eq(%w(Gemfile Gemfile.lock))
      end
    end

    context "when the directory has a dot dot" do
      let(:directory) { "/hello/.." }

      it "normalizes the directory" do
        expect(
          described_class.new(initial_dependency_files: files)
                    .current_dependency_files(job).map(&:name)
        ).to eq(%w(Gemfile Gemfile.lock))
      end
    end
  end
end
