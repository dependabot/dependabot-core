# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nimble/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Nimble::FileUpdater do
  let(:content) { File.read(File.join(__dir__, "fixtures", "example.nimble")) }
  let(:manifest) { Dependabot::DependencyFile.new(name: "example.nimble", content: content) }
  let(:updater) do
    described_class.new(dependency_files: [manifest], dependencies: dependencies, credentials: [])
  end
  let(:dependencies) { [dependency("chronos", "4.2.0", ">= 4.0.4", ">= 4.2.0")] }

  def requirement(string, group = "dependencies")
    { requirement: string, file: "example.nimble", groups: [group], source: nil }
  end

  def dependency(name, version, previous, current, group = "dependencies")
    Dependabot::Dependency.new(
      name: name,
      version: version,
      previous_version: nil,
      requirements: [requirement(current, group)],
      previous_requirements: [requirement(previous, group)],
      package_manager: "nimble"
    )
  end

  it_behaves_like "a dependency file updater"

  describe "#updated_dependency_files" do
    subject(:files) { updater.updated_dependency_files }

    it "changes only the version of that package" do
      expect(files.length).to eq(1)
      expect(files.first.content).to eq(content.sub('"chronos >= 4.0.4"', '"chronos >= 4.2.0"'))
    end

    context "with several packages, one of them in a task" do
      let(:dependencies) do
        [
          dependency("chronos", "4.2.0", ">= 4.0.4", ">= 4.2.0"),
          dependency("pinned", "1.3.0", "== 1.2.3", "== 1.3.0"),
          dependency("ranged", "1.5", ">= 1.0 & < 2.0", ">= 1.5 & < 2.0"),
          dependency("balls", "5.1", "^= 5.0", "^= 5.1", "test")
        ]
      end

      it "updates each in place" do
        expect(files.first.content).to include(
          '"chronos >= 4.2.0"', '"pinned == 1.3.0"', '"ranged >= 1.5 & < 2.0"', '"balls ^= 5.1"'
        )
        expect(files.first.content).to include('"nim >= 2.0.0"', '"unittest2 ~= 0.2.0"')
      end
    end

    context "when a package is required twice" do
      let(:content) { %(requires "foo >= 1.0"\ntaskRequires "test", "foo >= 1.0"\n) }
      let(:dependencies) do
        [Dependabot::Dependency.new(
          name: "foo",
          version: "1.4",
          requirements: [requirement(">= 1.4"), requirement(">= 1.4", "test")],
          previous_requirements: [requirement(">= 1.0"), requirement(">= 1.0", "test")],
          package_manager: "nimble"
        )]
      end

      it "updates both" do
        expect(files.first.content).to eq(%(requires "foo >= 1.4"\ntaskRequires "test", "foo >= 1.4"\n))
      end
    end

    context "when nothing changes" do
      let(:dependencies) { [dependency("chronos", "4.0.4", ">= 4.0.4", ">= 4.0.4")] }

      it "raises" do
        expect { files }.to raise_error("No files changed!")
      end
    end
  end
end
