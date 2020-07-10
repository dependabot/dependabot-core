require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/kiln/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Kiln::FileUpdater do
  #it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
        dependencies: dependencies,
        dependency_files: dependency_files,
        credentials: credentials,
        lockfile: lockfile,
    )
  end

  let(:credentials) do
    [{
         "type" => "git_source",
         "host" => "github.com",
         "username" => "x-access-token",
         "password" => "token"
     }, {
         "type" => "kiln",
         "variables" => {
             "aws_access_key_id" => "foo",
             "aws_secret_access_key" => "foo"
         }
     }]
  end
  let(:dependency_files) { [lockfile, kilnfile] }
  let(:dependencies) { [dependency] }

  let(:dependency) do
    Dependabot::Dependency.new(
        name: dependency_name,
        version: current_version,
        previous_version: previous_version,
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "kiln"
    )
  end
  let(:dependency_name) { "uaa" }
  let(:current_version) { "74.15.0" }
  let(:previous_version) { "74.14.0" }
  let(:previous_requirements) {
    [{
         requirement: "~74.16.0",
         file: "Kilnfile",
         source: {
             type: "compiled-releases",
             remote_path: "2.11/somewhere.tgz",
             sha: "old-sha"
         },
         groups: [:default]
     }]
  }
  let(:requirements) {
    [{
         requirement: "~74.16.0",
         file: "Kilnfile",
         source: {
             type: "bosh.io",
             remote_path: "bosh.io/uaa",
             sha: "sha"
         },
         groups: [:default]
     }]
  }
  let(:directory) { "/" }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
        name: "Kilnfile.lock",
        content: lockfile_body,
        directory: directory
    )
  end
  let(:kilnfile) do
    Dependabot::DependencyFile.new(
        name: "Kilnfile",
        content: kilnfile_body,
        directory: directory
    )
  end
  let(:lockfile_body) { fixture("kiln", lockfile_fixture_name) }
  let(:kilnfile_body) { fixture("kiln", kilnfile_fixture_name) }
  let(:expected_lockfile_body) { fixture("kiln", "expected", lockfile_fixture_name) }
  let(:lockfile_fixture_name) { "Kilnfile.lock" }
  let(:kilnfile_fixture_name) { "Kilnfile" }
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

      its(:length) { is_expected.to eq(1) }

    it "has updated dependency" do
      expect(updated_files[0].content).to eq(expected_lockfile_body)
    end

  end
end


