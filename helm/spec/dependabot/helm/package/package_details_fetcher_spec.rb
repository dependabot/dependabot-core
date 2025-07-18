# typed: false
# frozen_string_literal: true

require "dependabot/helm/package/package_details_fetcher"
require "excon"

RSpec.describe Dependabot::Helm::Package::PackageDetailsFetcher do
  let(:repo_name) { "prometheus-community" }
  let(:url) { "https://api.github.com/repos/#{repo_name}/helm-charts/releases" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "prometheus-community",
      version: "v1.0.0",
      requirements: [],
      package_manager: "helm"
    )
  end

  let(:credentials) do
    [
      Dependabot::Credential.new(
        type: "git_source",
        host: "github.com",
        username: "test-user",
        password: "test-password"
      )
    ]
  end
  let(:fetcher) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  describe "#fetch_tag_and_release_date_from_chart" do
    context "when the API call fails" do
      before do
        allow(Excon).to receive(:get).and_raise(Excon::Error.new("fail"))
      end

      it "returns an empty array" do
        expect(fetcher.fetch_tag_and_release_date_from_chart(repo_name)).to eq([])
      end
    end

    context "when the repo_name is empty" do
      it "returns an empty array" do
        expect(fetcher.fetch_tag_and_release_date_from_chart("")).to eq([])
      end
    end
  end

  describe "#parse_github_response" do
    let(:response) do
      Excon::Response.new(
        status: 200,
        body: [
          { "tag_name" => "v2.0.0", "published_at" => "2024-01-01T00:00:00Z" }
        ].to_json
      )
    end

    it "parses the response and returns GitTagWithDetail objects" do
      result = fetcher.parse_github_response(response)
      expect(result.first.tag).to eq("v2.0.0")
      expect(result.first.release_date).to eq("2024-01-01T00:00:00Z")
    end

    it "returns an empty array for invalid JSON" do
      bad_response = Excon::Response.new(status: 200, body: "not-json")
      expect(fetcher.parse_github_response(bad_response)).to eq([])
    end
  end

  describe "#fetch_tag_and_release_date_helm_chart_index" do
    let(:index_url) { "https://repo.broadcom.com/bitnami-files/index.yaml" }
    let(:chart_name) { "mongodb" }
    let(:yaml_body) do
      {
        "entries" => {
          "mongodb" => [
            { "version" => "16.5.26", "created" => "2025-06-26T14:37:16.802527078Z" },
            { "version" => "16.5.25", "created" => "2025-06-20T14:37:16.802527078Z" }
          ]
        }
      }.to_yaml
    end

    before do
      allow(Excon).to receive(:get).and_return(Excon::Response.new(status: 200, body: yaml_body))
    end

    it "returns GitTagWithDetail objects for each chart version" do
      result = fetcher.fetch_tag_and_release_date_helm_chart_index(index_url, chart_name)
      expect(result.map(&:tag)).to eq(["16.5.26", "16.5.25"])
      expect(result.map(&:release_date)).to eq(["2025-06-26T14:37:16.802527078Z", "2025-06-20T14:37:16.802527078Z"])
    end

    it "returns an empty array if chart_name is not found" do
      expect(fetcher.fetch_tag_and_release_date_helm_chart_index(index_url, "notfound")).to eq([])
    end
  end

  describe "#fetch_tags_with_release_date_using_oci" do
    let(:tags) { [] }
    let(:repo_url) { "oci://registry.example.com/myartifact" }
    let(:oras_response) do
      {
        "annotations" => {
          "org.opencontainers.image.created" => "2025-07-01T10:00:00Z"
        }
      }.to_json
    end

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return(oras_response)
    end

    it "returns GitTagWithDetail objects for each tag" do
      result = fetcher.fetch_tags_with_release_date_using_oci(tags, repo_url)
      expect(result.map(&:tag)).to eq(tags)
      expect(result.map(&:release_date)).to all(eq("2025-07-01T10:00:00Z"))
    end

    it "returns an empty array if tags is empty" do
      expect(fetcher.fetch_tags_with_release_date_using_oci([], repo_url)).to eq([])
    end
  end
end
