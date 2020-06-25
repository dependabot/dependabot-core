require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/kiln/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Kiln::UpdateChecker do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
        dependency: dependency,
        dependency_files: nil,
        credentials: nil,
        ignored_versions: nil,
        security_advisories: nil
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
  let(:dependency_files) { [lockfile, kilnfile] }
  let(:github_token) { "token" }
  let(:directory) { "/" }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:command) { ["kiln fetch-latest-version uaa", nil] }

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
         requirement: "~> 74.16.0",
         file: "Kilnfile",
         source: {
             type: "bosh.io"
         },
         groups: [:default]
     }]
  }

  describe 'latest version' do
    subject { checker.latest_version }

    before do
      response = []
      response << '74.16.5'
      response << '0'

      # expect
      allow(Open3).to receive(:capture2).with(*command).and_return(*response)
    end

    context "with a version that exist on bosh.io" do

      it { is_expected.to eq('74.16.5') }
    end

  end

end
