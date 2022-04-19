# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/nuget/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Nuget::MetadataFinder do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [{
        file: "my.csproj",
        requirement: dependency_version,
        groups: ["dependencies"],
        source: source
      }],
      package_manager: "nuget"
    )
  end
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_name) { "Microsoft.Extensions.DependencyModel" }
  let(:dependency_version) { "2.1.0" }
  let(:source) { nil }

  describe "#source_url" do
    subject(:source_url) { finder.source_url }
    let(:nuget_url) do
      "https://api.nuget.org/v3-flatcontainer/"\
      "microsoft.extensions.dependencymodel/2.1.0/"\
      "microsoft.extensions.dependencymodel.nuspec"
    end
    let(:nuget_response) do
      fixture(
        "nuspecs",
        "Microsoft.Extensions.DependencyModel.nuspec"
      )
    end

    before do
      stub_request(:get, nuget_url).to_return(status: 200, body: nuget_response)
      stub_request(:get, "https://example.com/status").to_return(
        status: 200,
        body: "Not GHES",
        headers: {}
      )
    end

    context "with a github link in the nuspec" do
      it { is_expected.to eq("https://github.com/dotnet/core-setup") }

      it "caches the call to nuget" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, nuget_url).once
      end
    end

    context "with a source" do
      let(:source) do
        {
          type: "nuget_repo",
          url: "https://www.myget.org/F/exceptionless/api/v3/index.json",
          source_url: nil,
          nuspec_url: "https://www.myget.org/F/exceptionless/api/v3/"\
                      "flatcontainer/microsoft.extensions."\
                      "dependencymodel/2.1.0/"\
                      "microsoft.extensions.dependencymodel.nuspec"
        }
      end

      let(:nuget_url) do
        "https://www.myget.org/F/exceptionless/api/v3/"\
        "flatcontainer/microsoft.extensions.dependencymodel/2.1.0/"\
        "microsoft.extensions.dependencymodel.nuspec"
      end

      it { is_expected.to eq("https://github.com/dotnet/core-setup") }

      it "caches the call to nuget" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, nuget_url).once
      end

      context "that has a source_url" do
        let(:source) do
          {
            type: "nuget_repo",
            url: "https://www.myget.org/F/exceptionless/api/v3/index.json",
            source_url: "https://github.com/my/repo",
            nuspec_url: nil
          }
        end

        it { is_expected.to eq("https://github.com/my/repo") }
      end

      context "that has neither a source_url nor a nuspec_url" do
        let(:source) do
          {
            type: "nuget_repo",
            url: "https://www.myget.org/F/exceptionless/api/v3/index.json",
            source_url: nil,
            nuspec_url: nil
          }
        end

        let(:nuget_url) do
          "https://api.nuget.org/v3-flatcontainer/"\
          "microsoft.extensions.dependencymodel/2.1.0/"\
          "microsoft.extensions.dependencymodel.nuspec"
        end

        it { is_expected.to eq("https://github.com/dotnet/core-setup") }
      end

      context "with details in the credentials (but no token)" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "nuget_feed",
            "url" => "https://www.myget.org/F/exceptionless/api/v3/"\
                     "index.json"
          }]
        end

        it { is_expected.to eq("https://github.com/dotnet/core-setup") }
      end

      context "that requires authentication" do
        before do
          stub_request(:get, nuget_url).to_return(status: 404)
          stub_request(:get, "https://www.myget.org/F/exceptionless/api/v3/index.json").to_return(status: 404)
        end

        it { is_expected.to be_nil }

        context "with details in the credentials" do
          before do
            stub_request(:get, nuget_url).
              with(basic_auth: %w(my passw0rd)).
              to_return(status: 200, body: nuget_response)
          end

          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }, {
              "type" => "nuget_feed",
              "url" => "https://www.myget.org/F/exceptionless/api/v3/"\
                       "index.json",
              "token" => "my:passw0rd"
            }]
          end

          it { is_expected.to eq("https://github.com/dotnet/core-setup") }
        end
      end

      context "that doesn't support .nuspec routes" do
        before do
          # registry doesn't support .nuspec route, so returns 404
          stub_request(:get, nuget_url).to_return(status: 404)
          # fallback begins by getting the search URL from the index
          stub_request(:get, "https://www.myget.org/F/exceptionless/api/v3/index.json").
            to_return(status: 200, body: fixture("nuspecs", "index.json"))
          # next query for the package at the search URL returned
          stub_request(:get, "https://azuresearch-usnc.nuget.org/query?prerelease=true&q=microsoft.extensions.dependencymodel&semVerLevel=2.0.0").
            to_return(status: 200, body: fixture("nuspecs", "microsoft.extensions.depdencymodel-results.json"))
        end

        # data was extracted from the projectUrl in the search results
        it { is_expected.to eq "https://github.com/dotnet/core-setup" }

        context "and it fails to get the index" do
          before do
            # registry is in a bad state
            stub_request(:get, nuget_url).to_return(status: 500)
            # it falls back to get search URL from the index, but it fails too
            stub_request(:get, "https://www.myget.org/F/exceptionless/api/v3/index.json").
              to_return(status: 500, body: "internal server error")
          end

          it { is_expected.to be_nil }
        end

        context "and it fails to get the search results" do
          before do
            # registry doesn't support .nuspec route, so returns 404
            stub_request(:get, nuget_url).to_return(status: 404)
            # fallback begins by getting the search URL from the index
            stub_request(:get, "https://www.myget.org/F/exceptionless/api/v3/index.json").
              to_return(status: 200, body: fixture("nuspecs", "index.json"))
            # oops, we're a little overloaded
            stub_request(:get, "https://azuresearch-usnc.nuget.org/query?prerelease=true&q=microsoft.extensions.dependencymodel&semVerLevel=2.0.0").
              to_return(status: 503, body: "")
          end

          it { is_expected.to be_nil }
        end
      end
    end
  end
end
