# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/ecosystem"
require "dependabot/config"
require "dependabot/errors"
require "dependabot/config/update_config"
require "dependabot/helm"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Helm::UpdateChecker do
  let(:repo_fixture_name) { "redis.json" }
  let(:repo_tags) { fixture("repo", "search", repo_fixture_name) }
  let(:repo_url) { "https://charts.bitnami.com/bitnami" }
  let(:source) { { tag: version } }
  let(:version) { "17.11.3" }
  let(:dependency_type) { { type: :helm_chart } }
  let(:dependency_name) { "redis" }
  let(:file_name) { "Chart.yaml" }
  let(:username) { "username" }
  let(:password) { "token" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: [{
        requirement: nil,
        groups: [],
        file: file_name,
        source: source,
        metadata: dependency_type
      }],
      package_manager: "helm"
    )
  end
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "helm_registry",
      "registry" => repo_url,
      "username" => username,
      "password" => password
    })]
  end
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored
    )
  end

  before do
    allow(Dependabot::Helm::Helpers).to receive(:search_releases)
      .with(dependency_name)
      .and_return(repo_tags)
  end

  it_behaves_like "an update checker"

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    it { is_expected.to eq(Dependabot::Docker::Version.new("20.11.3")) }

    context "when using a private repository" do
      before do
        allow(Dependabot::Helm::Helpers).to receive(:registry_login)
          .with(username, password, repo_url)
          .and_return("Login successful")

        allow(Dependabot::Helm::Helpers).to receive(:search_releases)
          .with("oci---localhost-5000/#{dependency_name}")
          .and_return(repo_tags)
      end

      let(:version) { "1.0.0" }
      let(:repo_url) { "oci://localhost:5000" }
      let(:repo_fixture_name) { "my_chart.json" }
      let(:dependency_name) { "my_chart" }
      let(:source) { { tag: version, registry: repo_url } }

      it { is_expected.to eq(Dependabot::Docker::Version.new("1.1.0")) }

      context "when authentication fails" do
        before do
          allow(Dependabot::Helm::Helpers).to receive(:registry_login)
            .with(username, password, repo_url)
            .and_raise(StandardError)
        end

        it "raises a to PrivateSourceAuthenticationFailure error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { latest_version }
            .to raise_error(error_class) do |error|
            expect(error.source).to eq("oci://localhost:5000")
          end
        end
      end
    end

    context "when dependency is a docker image" do
      let(:dependency_type) { { type: :docker_image } }
      let(:repo_fixture_name) { "ubuntu_no_latest.json" }
      let(:dependency_name) { "ubuntu" }
      let(:version) { "17.04" }
      let(:repo_tags) { fixture("docker", "registry_tags", repo_fixture_name) }
      let(:repo_url) { "https://registry.hub.docker.com/v2/library/ubuntu/" }

      before do
        auth_url = "https://auth.docker.io/token?service=registry.docker.io"
        stub_request(:get, auth_url)
          .and_return(status: 200, body: { token: "token" }.to_json)

        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: repo_tags)
      end

      it { is_expected.to eq(Dependabot::Docker::Version.new("17.10")) }
    end
  end

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "when the dependency is outdated" do
      let(:version) { "17.04" }

      it { is_expected.to be_truthy }
    end

    context "when the dependency is up-to-date" do
      let(:version) { "20.11.3" }

      it { is_expected.to be_falsey }
    end

    context "when the version is numeric" do
      let(:version) { "1234567890" }

      it { is_expected.to be_falsey }
    end
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements }

    context "when specified with a tag in helm chart" do
      it "updates the requirement" do
        expect(checker.updated_requirements).to eq(
          [{
            groups: [],
            file: "Chart.yaml",
            metadata: { type: :helm_chart },
            requirement: "20.11.3",
            source: { tag: "17.11.3" }
          }]
        )
      end

      context "when specified with a tag in values" do
        let(:file_name) { "values.yaml" }

        it "updates the requirement" do
          expect(checker.updated_requirements).to eq(
            [{
              groups: [],
              file: "values.yaml",
              metadata: { type: :helm_chart },
              requirement: "20.11.3",
              source: { tag: "17.11.3" }
            }]
          )
        end
      end
    end
  end
end
