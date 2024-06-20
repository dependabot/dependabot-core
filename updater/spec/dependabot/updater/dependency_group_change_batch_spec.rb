# typed: false
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/job"
require "dependabot/source"
require "dependabot/updater/operations"

require "spec_helper"

RSpec.describe Dependabot::Updater::DependencyGroupChangeBatch do
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
      expect(described_class.new(initial_dependency_files: files)
        .current_dependency_files(job).map(&:name)).to eq(%w(Gemfile Gemfile.lock))
    end

    context "when the directory has a dot" do
      let(:directory) { "/." }

      it "normalizes the directory" do
        expect(described_class.new(initial_dependency_files: files)
          .current_dependency_files(job).map(&:name)).to eq(%w(Gemfile Gemfile.lock))
      end
    end

    context "when the directory has a dot dot" do
      let(:directory) { "/hello/.." }

      it "normalizes the directory" do
        expect(described_class.new(initial_dependency_files: files)
          .current_dependency_files(job).map(&:name)).to eq(%w(Gemfile Gemfile.lock))
      end
    end

    context "when the :dependency_has_directory ff is enabled" do
      before do
        Dependabot::Experiments.register(:dependency_has_directory, true)
      end

      after do
        Dependabot::Experiments.reset!
      end

      let(:dependency_change) do
        Dependabot::DependencyChange.new(
          job: job,
          updated_dependency_files: updated_dependency_files,
          updated_dependencies: updated_dependencies,
          dependency_group: group,
        )
      end

      let(:updated_dependency_files) do
        [
          Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-updated-gemfile", directory: "/"),
          Dependabot::DependencyFile.new(name: "Gemfile.lock", content: "mock-updated-gemfile-lock", directory: "/hello/.."),
          Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-updated-package-json", directory: "/elsewhere"),
          Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-package-json", directory: "unknown"),
          Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-package-json", directory: "../../oob")
        ]
      end

      let(:test_dependency1) do
        Dependabot::Dependency.new(
          name: "test-dependency-1",
          package_manager: "bundler",
          version: "1.1.0",
          requirements: [
            {
              file: "Gemfile",
              requirement: "~> 1.1.0",
              groups: ["test"],
              source: nil
            }
          ],
          directory: "/"
        )
      end

      let(:test_dependency2) do
        Dependabot::Dependency.new(
          name: "test-dependency-2",
          package_manager: "bundler",
          version: "1.1.0",
          requirements: [
            {
              file: "Gemfile",
              requirement: "~> 1.1.0",
              groups: ["test"],
              source: nil
            }
          ],
          directory: "/hello/.."
        )
      end

      let(:updated_dependencies) do
        [test_dependency1, test_dependency2]
      end

      let(:group) do
        Dependabot::DependencyGroup.new(
          name: "test",
          rules: { patterns: ["test-*"] }
        )
      end

      it "still tracks the updated_dependencies in the global list" do
        batch = described_class.new(initial_dependency_files: files)
        batch.merge(dependency_change)

        expect(batch.updated_dependencies).to eq(updated_dependencies)
      end

      it "tracks the updated dependencies in the appropriate updated_dependency_files" do
        batch = described_class.new(initial_dependency_files: files)
        batch.merge(dependency_change)

        # FIXME: All of the files in the dependency_file_batch will contain a copy of the updated dependencies.
        # Eventually this should be narrowed down so that only the files that were modified
        # by the newly merged dependency_change have their updated_dependencies updated.
        dependency_file_batch = batch.instance_variable_get(:@dependency_file_batch)
        expect(dependency_file_batch["/Gemfile"][:updated_dependencies]).to include(test_dependency1)
        expect(dependency_file_batch["/Gemfile"][:updated_dependencies]).to include(test_dependency2)
        expect(dependency_file_batch["/Gemfile.lock"][:updated_dependencies]).to include(test_dependency1)
        expect(dependency_file_batch["/Gemfile.lock"][:updated_dependencies]).to include(test_dependency2)
      end
    end
  end
end
