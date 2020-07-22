require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/kiln/update_checker"
require "dependabot/kiln/requirement"
require "dependabot/kiln/version"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Kiln::UpdateChecker do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
        dependency: dependency,
        dependency_files: dependency_files,
        credentials: credentials,
        ignored_versions: nil,
        security_advisories: nil
    )
  end
  let(:dependency_files) { [lockfile, kilnfile] }
  let(:directory) { '/' }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
        name: "Kilnfile.lock",
        content: '',
        directory: directory
    )
  end
  let(:kilnfile) do
    Dependabot::DependencyFile.new(
        name: "Kilnfile",
        content: '',
        directory: directory
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
  let(:github_token) { "token" }
  let(:directory) { "/" }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  # let(:lockfile_body) { fixture("ruby", "lockfiles", lockfile_fixture_name) }
  let(:command) { [/kiln find-release-version --r uaa -kf .*\/Kilnfile -vr aws_access_key_id=foo -vr aws_secret_access_key=foo/] }

  let(:dependency) do
    Dependabot::Dependency.new(
        name: dependency_name,
        version: current_version,
        requirements: requirements,
        package_manager: "kiln"
    )
  end
  let(:dependency_name) { "uaa" }
  let(:current_version) { "74.16.0" }
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
  let(:updated_requirements) {
    [{
         requirement: "~74.16.0",
         file: "Kilnfile",
         source: {
             type: "compiled-releases",
             remote_path: "2.11/uaa/uaa-74.21.0-ubuntu-xenial-621.76.tgz",
             sha: "updated-sha"
         },
         groups: [:default]
     }]
  }

  describe 'latest version' do
    subject { checker.latest_version }
    let(:process_status) { double }

    before do
      allow(process_status).to receive(:success?).and_return true
      allow(Open3).to receive(:capture3).with(*command).and_return(response, '', process_status)
    end

    context "with a version that exist in s3" do
      let(:response) { "... \n{\"version\":\"74.21.0\",\"remote_path\":\"2.11/uaa/uaa-74.21.0-ubuntu-xenial-621.76.tgz\"}" }

      it { is_expected.to eq(Dependabot::Kiln::Version.new('74.21.0')) }
    end

    context "with a version that exist in bosh.io" do
      let(:response) { "{\"version\":\"74.21.0\",\"remote_path\":\"2.11/uaa/uaa-74.21.0-ubuntu-xenial-621.76.tgz\"}" }

      it { is_expected.to eq(Dependabot::Kiln::Version.new('74.21.0')) }
    end

    context "when no new version satifies the version constaint" do
      let(:response) { "{\"version\":\"74.16.0\",\"remote_path\":\"https://bosh.io/d/github.com/cloudfoundry/uaa-release?v=74.16.0\",\"source\":\"bosh.io\",\"sha\":\"991f8aca30ed1bada8a7a1a3582d0dea1ef8017e\"}" }

      it { is_expected.to eq(Dependabot::Kiln::Version.new('74.16.0')) }
    end
    describe "not found release name" do
      let(:response) { "{\"version\":\"\",\"remote_path\":\"\"}" }

      context "with no version at all" do
        it { is_expected.to eq(Dependabot::Kiln::Version.new('')) }
      end
    end

  end

  describe 'update requirements' do
    subject { checker.updated_requirements }
    let(:process_status) { double }

    before do
      allow(process_status).to receive(:success?).and_return true
      allow(Open3).to receive(:capture3).with(*command).and_return(response, nil, process_status)
    end

    context "with a version that exist" do
      let(:response) { "{\"version\":\"74.21.0\",\"remote_path\":\"2.11/uaa/uaa-74.21.0-ubuntu-xenial-621.76.tgz\",\"source\":\"compiled-releases\",\"sha\":\"updated-sha\"}" }

      it { is_expected.to eq(updated_requirements) }
    end

    describe "not found release name" do
      let(:response) { "{\"version\":\"\",\"remote_path\":\"\",\"source\":\"\",\"sha\":\"\"}" }

      context "with no version at all" do
        it { is_expected.to eq(dependency.requirements) }
      end
    end

  end

end
