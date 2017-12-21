# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/python/pipfile"
require "dependabot/shared_helpers"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Python::Pipfile do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: [pipfile, lockfile],
      dependencies: [dependency],
      credentials: [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end
  let(:pipfile) do
    Dependabot::DependencyFile.new(
      content: pipfile_body,
      name: "Pipfile"
    )
  end
  let(:pipfile_body) do
    fixture("python", "pipfiles", "version_not_specified")
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      content: lockfile_body,
      name: "Pipfile.lock"
    )
  end
  let(:lockfile_body) do
    fixture("python", "lockfiles", "version_not_specified.lock")
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "2.18.4",
      previous_version: "2.18.0",
      package_manager: "pipfile",
      requirements: [
        { requirement: "*", file: "Pipfile", source: nil, groups: ["default"] }
      ],
      previous_requirements: [
        { requirement: "*", file: "Pipfile", source: nil, groups: ["default"] }
      ]
    )
  end
  let(:dependency_name) { "requests" }
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(2) }

    describe "the updated Pipfile" do
      subject(:updated_pipfile) do
        updated_files.find { |f| f.name == "Pipfile" }
      end

      its(:content) { is_expected.to eq(pipfile_body) }
    end

    describe "the updated Pipfile.lock" do
      let(:updated_lockfile) do
        updated_files.find { |f| f.name == "Pipfile.lock" }
      end

      let(:json_lockfile) { JSON.parse(updated_lockfile.content) }

      it "updates only what it needs to" do
        expect(json_lockfile["default"]["requests"]["version"]).
          to eq("==2.18.4")
        expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==3.2.3")
        expect(json_lockfile["_meta"]["hash"]).
          to eq(JSON.parse(lockfile_body)["_meta"]["hash"])
        expect(
          json_lockfile["_meta"]["host-environment-markers"]["python_version"]
        ).to eq("2.7")
      end

      describe "with dependency names that need to be normalised" do
        let(:dependency_name) { "Requests" }
        let(:pipfile_body) { fixture("python", "pipfiles", "hard_names") }
        let(:lockfile_body) do
          fixture("python", "lockfiles", "hard_names.lock")
        end

        it "updates only what it needs to" do
          expect(json_lockfile["default"]["requests"]["version"]).
            to eq("==2.18.4")
          expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==3.2.3")
        end
      end
    end
  end

  describe "#updated_pipfile_content" do
    subject(:updated_pipfile_content) { updater.send(:updated_pipfile_content) }

    context "with single quotes" do
      let(:pipfile_body) { fixture("python", "pipfiles", "with_quotes") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "python_decouple",
          version: "3.2",
          previous_version: "3.1",
          package_manager: "pipfile",
          requirements: [
            {
              requirement: "==3.2",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }
          ],
          previous_requirements: [
            {
              requirement: "==3.1",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }
          ]
        )
      end

      it { is_expected.to include(%q('python_decouple' = "==3.2")) }
    end

    context "with double quotes" do
      let(:pipfile_body) { fixture("python", "pipfiles", "with_quotes") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.18.4",
          previous_version: "2.18.0",
          package_manager: "pipfile",
          requirements: [
            {
              requirement: "==2.18.4",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }
          ],
          previous_requirements: [
            {
              requirement: "==2.18.0",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }
          ]
        )
      end

      it { is_expected.to include('"requests" = "==2.18.4"') }
    end

    context "without quotes" do
      let(:pipfile_body) { fixture("python", "pipfiles", "with_quotes") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "pytest",
          version: "3.3.1",
          previous_version: "3.2.3",
          package_manager: "pipfile",
          requirements: [
            {
              requirement: "==3.3.1",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }
          ],
          previous_requirements: [
            {
              requirement: "==3.2.3",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }
          ]
        )
      end

      it { is_expected.to include(%(\npytest = "==3.3.1"\n)) }
      it { is_expected.to include(%(\npytest-extension = "==3.2.3"\n)) }
      it { is_expected.to include(%(\nextension-pytest = "==3.2.3"\n)) }
    end
  end
end
