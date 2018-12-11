# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/go/modules"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Go::Modules do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  let(:files) { [go_mod, go_sum] }
  let(:go_mod) do
    Dependabot::DependencyFile.new(name: "go.mod", content: go_mod_body)
  end
  let(:go_mod_body) { fixture("go", "go_mods", go_mod_fixture_name) }
  let(:go_mod_fixture_name) { "go.mod" }

  let(:go_sum) do
    Dependabot::DependencyFile.new(name: "go.sum", content: go_sum_body)
  end
  let(:go_sum_body) { fixture("go", "go_mods", go_sum_fixture_name) }
  let(:go_sum_fixture_name) { "go.sum" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      previous_version: dependency_previous_version,
      previous_requirements: previous_requirements,
      package_manager: "go_modules"
    )
  end
  let(:dependency_name) { "rsc.io/quote" }
  let(:dependency_version) { "v1.5.2" }
  let(:dependency_previous_version) { "v1.5.1" }
  let(:requirements) do
    [{
      file: "go.mod",
      requirement: dependency_version,
      groups: [],
      source: {
        type: "default",
        source: "rsc.io/quote"
      }
    }]
  end
  let(:previous_requirements) do
    [{
      file: "go.mod",
      requirement: dependency_previous_version,
      groups: [],
      source: {
        type: "default",
        source: "rsc.io/quote"
      }
    }]
  end
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently, and returns DependencyFiles" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    it { expect { updated_files }.to_not output.to_stdout }

    it "includes an updated go.mod" do
      expect(updated_files.find { |f| f.name == "go.mod" }).to_not be_nil
    end

    it "includes an updated go.sum" do
      expect(updated_files.find { |f| f.name == "go.sum" }).to_not be_nil
    end

    context "without a go.sum" do
      let(:files) { [go_mod] }

      it "doesn't include a go.sum" do
        expect(updated_files.find { |f| f.name == "go.sum" }).to be_nil
      end
    end
  end
end
