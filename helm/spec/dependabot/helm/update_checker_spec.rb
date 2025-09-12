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

    it { is_expected.to eq(Dependabot::Helm::Version.new("20.11.3")) }

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

      it { is_expected.to eq(Dependabot::Helm::Version.new("17.10")) }

      context "when the docker image is can't be updated" do
        let(:version) { "latest" }

        it { is_expected.to be_nil }
      end
    end

    context "when oci is not in repo" do
      before do
        allow(checker).to receive(:fetch_releases_with_helm_cli)
          .with(dependency_name, "oci---registry-sweet-security-helm", repo_url)
          .and_return(nil)
        allow(Dependabot::Helm::Helpers).to receive(:fetch_oci_tags)
          .with("registry.sweet.security/helm/frontierchart")
          .and_return(
            "1.0.119807+c2277fddd003556d4982b86ef4e77fc84a41ed79\n1.0.124446+3123f85bdf6d8309d3d601938564a996f5cad238"
          )
      end

      let(:credentials) { [] }
      let(:version) { "1.0.119807+c2277fddd003556d4982b86ef4e77fc84a41ed79" }
      let(:dependency_name) { "frontierchart" }
      let(:repo_url) { "oci://registry.sweet.security/helm" }
      let(:source) { { tag: version, registry: "oci://registry.sweet.security/helm" } }

      it "returns the latest version" do
        expect(checker.latest_version).to eq(
          Dependabot::Helm::Version.new("1.0.124446+3123f85bdf6d8309d3d601938564a996f5cad238")
        )
      end

      context "when tags include non-version tags like SHA256 hashes and metadata files" do
        before do
          allow(Dependabot::Helm::Helpers).to receive(:fetch_oci_tags)
            .with("registry.sweet.security/helm/frontierchart")
            .and_return(
              "1.0.119807+c2277fddd003556d4982b86ef4e77fc84a41ed79\n" \
              "1.0.124446+3123f85bdf6d8309d3d601938564a996f5cad238\n" \
              "sha256-bbccb29e4f20037bc6c3319199138172c044d29c514431a11f0f2bfd9b694d6d\n" \
              "sha256-bbccb29e4f20037bc6c3319199138172c044d29c514431a11f0f2bfd9b694d6d.att\n" \
              "sha256-bbccb29e4f20037bc6c3319199138172c044d29c514431a11f0f2bfd9b694d6d.sig\n" \
              "sha256-bbccb29e4f20037bc6c3319199138172c044d29c514431a11f0f2bfd9b694d6d.metadata\n" \
              "1.1.0"
            )
        end

        it "filters out non-version tags and returns the latest valid version" do
          expect(checker.latest_version).to eq(
            Dependabot::Helm::Version.new("1.1.0")
          )
        end
      end
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

  describe "#filter_valid_releases" do
    let(:releases) do
      [
        { "version" => "17.0.0" },
        { "version" => "17.7.1" }, # This version caused the original Sorbet error
        { "version" => "18.0.0" },
        { "version" => "19.0.0" },
        { "version" => "20.0.0" }
      ]
    end

    context "when ignore_requirements contains Docker::Requirement objects" do
      let(:docker_requirement) { Dependabot::Docker::Requirement.new(">= 18.0.0") }

      before do
        allow(checker).to receive(:ignore_requirements).and_return([docker_requirement])
      end

      it "does not cause Sorbet type validation errors with Docker requirements processing Helm versions" do
        # This test specifically validates the fix for:
        # Parameter 'version': Expected type Dependabot::Docker::Version, got type Dependabot::Helm::Version
        expect { checker.send(:filter_valid_releases, releases) }.not_to raise_error
      end

      it "ignores Docker::Requirement objects due to instance_of? check" do
        # Since Docker::Requirement is not instance_of?(Dependabot::Requirement),
        # it should be ignored and not filter any versions
        result = checker.send(:filter_valid_releases, releases)

        # Should only filter out versions <= current version (17.11.3)
        # Docker requirements should be ignored due to instance_of? check
        expect(result.map { |r| r["version"] }).to contain_exactly("18.0.0", "19.0.0", "20.0.0")
      end
    end

    context "when ignore_requirements contains mixed requirement types" do
      let(:docker_requirement) { Dependabot::Docker::Requirement.new(">= 18.0.0") }
      let(:mock_base_requirement) do
        req = double("MockBaseRequirement")
        allow(req).to receive(:instance_of?).with(Dependabot::Requirement).and_return(true)
        allow(req).to receive(:satisfied_by?) do |version|
          # Mock requirement ">= 19.0.0"
          version.to_s >= "19.0.0"
        end
        req
      end

      before do
        allow(checker).to receive(:ignore_requirements).and_return([docker_requirement, mock_base_requirement])
      end

      it "only processes requirements that pass instance_of? check" do
        result = checker.send(:filter_valid_releases, releases)

        # Should filter out:
        # 1. Versions <= current version (17.11.3): 17.0.0, 17.7.1
        # 2. Versions matching mock_base_requirement >= 19.0.0: 19.0.0, 20.0.0
        # Docker requirement should be ignored
        expect(result.map { |r| r["version"] }).to contain_exactly("18.0.0")
      end

      it "does not cause cross-package type validation errors" do
        expect { checker.send(:filter_valid_releases, releases) }.not_to raise_error
      end
    end
  end

  describe "#filter_valid_versions" do
    let(:all_versions) { ["17.0.0", "17.7.1", "18.0.0", "19.0.0", "20.0.0"] }

    context "when ignore_requirements contains Docker::Requirement objects" do
      let(:docker_requirement) { Dependabot::Docker::Requirement.new(">= 18.0.0") }

      before do
        allow(checker).to receive(:ignore_requirements).and_return([docker_requirement])
      end

      it "does not cause Sorbet type validation errors with Docker requirements processing Helm versions" do
        # This test specifically validates the fix for:
        # Parameter 'version': Expected type Dependabot::Docker::Version, got type Dependabot::Helm::Version
        expect { checker.send(:filter_valid_versions, all_versions) }.not_to raise_error
      end

      it "ignores Docker::Requirement objects due to instance_of? check" do
        # Since Docker::Requirement is not instance_of?(Dependabot::Requirement),
        # it should be ignored and not filter any versions
        result = checker.send(:filter_valid_versions, all_versions)

        # Should only filter out versions <= current version (17.11.3)
        # Docker requirements should be ignored due to instance_of? check
        expect(result).to contain_exactly("18.0.0", "19.0.0", "20.0.0")
      end
    end

    context "when ignore_requirements contains mixed requirement types" do
      let(:docker_requirement) { Dependabot::Docker::Requirement.new(">= 18.0.0") }
      let(:mock_base_requirement) do
        req = double("MockBaseRequirement")
        allow(req).to receive(:instance_of?).with(Dependabot::Requirement).and_return(true)
        allow(req).to receive(:satisfied_by?) do |version|
          # Mock requirement ">= 19.0.0"
          Dependabot::Helm::Version.new(version.to_s) >= Dependabot::Helm::Version.new("19.0.0")
        end
        req
      end

      before do
        allow(checker).to receive(:ignore_requirements).and_return([docker_requirement, mock_base_requirement])
      end

      it "only processes requirements that pass instance_of? check" do
        result = checker.send(:filter_valid_versions, all_versions)

        # Should filter out:
        # 1. Versions <= current version (17.11.3): 17.0.0, 17.7.1
        # 2. Versions matching mock_base_requirement >= 19.0.0: 19.0.0, 20.0.0
        # Docker requirement should be ignored
        expect(result).to contain_exactly("18.0.0")
      end

      it "does not cause cross-package type validation errors" do
        expect { checker.send(:filter_valid_versions, all_versions) }.not_to raise_error
      end
    end

    context "reproducing the original error scenario" do
      let(:version) { "17.7.1" } # The version that caused the original error
      let(:docker_requirement) { Dependabot::Docker::Requirement.new(">= 17.7.0") }

      before do
        allow(checker).to receive(:ignore_requirements).and_return([docker_requirement])
      end

      it "handles the problematic version 17.7.1 without Sorbet errors" do
        # This specifically tests the scenario mentioned in the original error:
        # Dependabot::Helm::Version "17.7.1" being passed to Docker::Requirement#satisfied_by?
        expect { checker.send(:filter_valid_versions, ["17.7.1", "18.0.0"]) }.not_to raise_error
      end
    end
  end

  describe "#fetch_helm_chart_index" do
    subject(:latest_chart_version) { checker.send(:fetch_latest_chart_version) }

    let(:credentials) { [] }
    let(:index_content) { fixture("helm", "registry", "bitnami.yaml") }
    let(:source) { { registry: repo_url, tag: version } }

    before do
      allow(Dependabot::Helm::Helpers).to receive(:search_releases)
        .with(anything)
        .and_return("")

      stub_request(:get, "#{repo_url}/index.yaml")
        .to_return(
          status: 200,
          body: index_content
        )
    end

    context "when helm CLI search fails" do
      it "falls back to fetching from index.yaml" do
        expect(Dependabot::Helm::Helpers).to receive(:search_releases)
        expect(checker).to receive(:fetch_releases_from_index).and_call_original
        expect(checker).to receive(:fetch_helm_chart_index).with("#{repo_url}/index.yaml").and_call_original

        latest_chart_version
      end

      it "returns the latest version from the index" do
        expect(latest_chart_version).to eq(Dependabot::Helm::Version.new("20.11.3"))
      end

      context "when the request returns a string" do
        before do
          stub_request(:get, "#{repo_url}/index.yaml")
            .to_return(
              status: 200,
              body: "Not found"
            )
        end

        it "returns nil" do
          expect(latest_chart_version).to be_nil
        end

        it "logs an error" do
          expect(Dependabot.logger).to receive(:error).with(/Error parsing Helm index/)
          latest_chart_version
        end
      end
    end

    context "with an oci protocol" do
      before do
        allow(checker).to receive(:fetch_latest_oci_tag)
          .with(dependency_name, repo_url)
          .and_return(nil)
      end

      let(:repo_url) { "oci://charts.bitnami.com/bitnami" }

      it "converts OCI URL to HTTPS when making the request" do
        expect(Excon).to receive(:get)
          .with(
            "#{repo_url.gsub('oci', 'https')}/index.yaml",
            idempotent: true,
            middlewares: anything
          )

        latest_chart_version
      end
    end

    describe "#fetch_tags_with_release_date_using_oci" do
      let(:tags) { ["1.0.0", "1.1.0", "2.0.0+build.123", "latest"] }
      let(:oci_response) do
        {
          "annotations" => {
            "org.opencontainers.image.created" => "2024-01-15T10:00:00Z"
          }
        }.to_json
      end

      before do
        allow(Dependabot::Helm::Helpers).to receive(:fetch_tags_with_release_date_using_oci)
          .and_return(oci_response)
      end

      context "when OCI response is empty" do
        let(:tags) { ["1.0.0", "1.1.0"] }

        before do
          allow(Dependabot::Helm::Helpers).to receive(:fetch_tags_with_release_date_using_oci)
            .with(repo_url, "1.0.0").and_return("")
          allow(Dependabot::Helm::Helpers).to receive(:fetch_tags_with_release_date_using_oci)
            .with(repo_url, "1.1.0").and_return({ "annotations" => {} }.to_json)
        end

        it "skips tags with empty responses" do
          result = checker.send(:fetch_tags_with_release_date_using_oci, tags, repo_url)

          expect(result.length).to eq(1)
          expect(result.first.tag).to eq("1.1.0")
        end
      end

      it "fetches release dates for each tag" do
        result = checker.send(:fetch_tags_with_release_date_using_oci, tags, repo_url)

        expect(result).to be_an(Array)
        expect(result.length).to eq(4)
        # expect(result).to all(be_a(Dependabot::Helm::GitTagWithDetail))
      end

      it "extracts release date from OCI annotations" do
        result = checker.send(:fetch_tags_with_release_date_using_oci, tags, repo_url)

        expect(result.first.release_date).to eq("2024-01-15T10:00:00Z")
      end
    end
  end
end
