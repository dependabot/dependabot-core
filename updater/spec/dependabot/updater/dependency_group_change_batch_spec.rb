# typed: false
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/job"
require "dependabot/source"
require "dependabot/updater/operations"

require "spec_helper"

RSpec.describe Dependabot::Updater::DependencyGroupChangeBatch do
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
        updated_dependency_files: [updated_file, vendored_file]
      )

      batch.merge(change)

      expect(batch.updated_dependency_files).to contain_exactly(updated_file, vendored_file)
    end

    it "increments repeated changes and retains the newest file" do
      first_change = instance_double(
        Dependabot::DependencyChange,
        updated_dependencies: [],
        updated_dependency_files: [updated_file]
      )
      second_change = instance_double(
        Dependabot::DependencyChange,
        updated_dependencies: [],
        updated_dependency_files: [second_update]
      )

      batch.merge(first_change)
      expect(logger).to receive(:debug).with("  - /Gemfile.lock ( Changed 2 times )")
      batch.merge(second_change)

      expect(batch.updated_dependency_files).to eq([second_update])
    end
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
