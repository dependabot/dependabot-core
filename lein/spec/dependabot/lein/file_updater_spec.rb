# frozen_string_literal: true

require "spec_helper"
require "dependabot/lein/file_updater"
require "dependabot/dependency_file"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Lein::FileUpdater do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:files) { [project_file] }
  let(:project_file_fixture_name) { "dakrone_clj_http.clj" }
  let(:project_file) do
    Dependabot::DependencyFile.new(
      content: fixture("project_files", project_file_fixture_name),
      name: "project.clj"
    )
  end

  describe "without a project.clj" do
    it "raises an error" do
      args = { dependency_files: [], dependencies: [], credentials: credentials }

      expect { described_class.new(**args) }.to raise_error("No project.clj!")
    end
  end

  describe "an abbreviated dependency" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "commons-io:commons-io",
        version: "2.7",
        requirements:
        [{ file: "pom.xml", requirement: "2.7", groups: [], source: nil }],
        previous_version: "2.6",
        previous_requirements:
          [{ file: "pom.xml", requirement: "2.6", groups: [], source: nil }],
        package_manager: "lein"
      )
    end

    describe "#updated_dependency_files" do
      subject(:updated_files) { updater.updated_dependency_files }

      it "returns DependencyFile objects" do
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
      end

      it "returns the project.clj" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.name).to eq("project.clj")
      end

      describe "updated project.clj" do
        subject(:updated_project_file) { updated_files.find { |f| f.name == "project.clj" } }

        it "has updated commons-io" do
          expect(updated_project_file.content).to include(%([commons-io "2.7"]))
        end

        it "has not changed anything else" do
          expected_content = updated_project_file.content.gsub(%([commons-io "2.7"]), %([commons-io "2.6"]))

          expect(project_file.content).to eq(expected_content)
        end
      end
    end
  end

  describe "a fully qualified dependency" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "org.apache.httpcomponents:httpmime",
        version: "4.5.15",
        requirements:
        [{ file: "pom.xml", requirement: "4.5.15", groups: [], source: nil }],
        previous_version: "4.5.13",
        previous_requirements:
        [{ file: "pom.xml", requirement: "4.5.13", groups: [], source: nil }],
        package_manager: "lein"
      )
    end

    describe "#updated_dependency_files" do
      subject(:updated_files) { updater.updated_dependency_files }

      it "returns DependencyFile objects" do
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
      end

      it "returns the project.clj" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.name).to eq("project.clj")
      end

      describe "updated project.clj" do
        subject(:updated_project_file) { updated_files.find { |f| f.name == "project.clj" } }

        it "has updated commons-io" do
          expect(updated_project_file.content).to include(%([org.apache.httpcomponents/httpmime "4.5.15"]))
        end

        it "has not changed anything else" do
          expected_content = updated_project_file.content.gsub(
            %([org.apache.httpcomponents/httpmime "4.5.15"]),
            %([org.apache.httpcomponents/httpmime "4.5.13"])
          )

          expect(project_file.content).to eq(expected_content)
        end
      end
    end
  end
end
