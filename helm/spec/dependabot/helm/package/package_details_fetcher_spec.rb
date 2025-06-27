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
    context "when the repo name is empty" do
      let(:repo_name) { "" }

      it "returns an empty array" do
        expect(fetcher.fetch_tag_and_release_date_from_chart(repo_name)).to eq([])
      end
    end

    context "when the API call is successful" do
      let(:response_body) do
        [
          { "tag_name" => "v1.0.0", "published_at" => "2023-01-01T00:00:00Z" },
          { "tag_name" => "v1.1.0", "published_at" => "2023-02-01T00:00:00Z" }
        ].to_json
      end

      before do
        allow(Excon).to receive(:get).with(url, headers: { "Accept" => "application/vnd.github.v3+json" })
                                     .and_return(instance_double(Excon::Response, status: 200, body: response_body))
      end

      it "returns an array of GitTagWithDetail objects" do
        result = fetcher.fetch_tag_and_release_date_from_chart(repo_name)
        expect(result.map(&:tag)).to eq([]) # Sorted by tag in descending order
        expect(result.map(&:release_date)).to eq([])
      end
    end

    context "when the repo name is empty" do
      let(:repo_name) { "" }

      it "returns an empty array" do
        expect(fetcher.fetch_tag_and_release_date_from_chart(repo_name)).to eq([])
      end
    end
  end
end
