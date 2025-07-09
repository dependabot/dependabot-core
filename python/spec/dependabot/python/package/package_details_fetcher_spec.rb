# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/python/package/package_details_fetcher"

RSpec.describe Dependabot::Python::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:dependency_name) { "requests" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "2.4.1",
      requirements: [{
        requirement: "==2.4.1",
        file: "requirements.txt",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "pip"
    )
  end

  let(:dependency_files) { [] }
  let(:credentials) { [] }

  let(:registry_base) { "https://pypi.org/simple" }
  let(:registry_url) { "#{registry_base}/#{dependency_name}/" }
  let(:json_url) { "https://pypi.org/pypi/#{dependency_name}/json" }

  let(:expected_versions) { ["2.32.3", "2.27.0"] }

  let(:expected_releases) do
    [
      Dependabot::Package::PackageRelease.new(
        version: Dependabot::Python::Version.new("2.32.3"),
        released_at: nil,
        yanked: false,
        yanked_reason: nil,
        downloads: -1,
        url: "https://files.pythonhosted.org/packages/f9/9b/335f9764261e915ed497fcdeb11df5dfd6f7bf257d4a6a2a686d80da4d54/requests-2.32.3-py3-none-any.whl",
        package_type: nil,
        language: Dependabot::Package::PackageLanguage.new(
          name: "python",
          version: nil,
          requirement: Dependabot::Python::Requirement.new([">=3.8"])
        )
      ),
      Dependabot::Package::PackageRelease.new(
        version: Dependabot::Python::Version.new("2.27.0"),
        released_at: nil,
        yanked: false,
        yanked_reason: nil,
        downloads: -1,
        url: "https://files.pythonhosted.org/packages/47/01/f420e7add78110940639a958e5af0e3f8e07a8a8b62049bac55ee117aa91/requests-2.27.0-py2.py3-none-any.whl",
        package_type: nil,
        language: Dependabot::Package::PackageLanguage.new(
          name: "python",
          version: nil,
          requirement: Dependabot::Python::Requirement.new([">=2.7", "!=3.0.*", "!=3.1.*", "!=3.2.*", "!=3.3.*",
                                                            "!=3.4.*", "!=3.5.*"])
        )
      )
    ]
  end

  describe "#fetch" do
    subject(:fetch) { fetcher.fetch }

    context "with a valid JSON response" do
      before do
        stub_request(:get, json_url).to_return(status: 200,
                                               body: fixture("releases_api", "pypi", "pypi_json_response.json"))
        stub_request(:get, registry_url).to_return(status: 200,
                                                   body: fixture("releases_api", "simple", "simple_index.html"))
      end

      it "fetches data from JSON registry first and returns correct package releases" do
        result = fetch

        expect(result.releases).not_to be_empty
        expect(a_request(:get, json_url)).to have_been_made.once
        expect(a_request(:get, registry_url)).not_to have_been_made

        expect(result.releases.map(&:version)).to match_array(expected_releases.map(&:version))
      end
    end

    context "when JSON response is empty" do
      before do
        stub_request(:get, json_url).to_return(status: 200,
                                               body: fixture("releases_api", "pypi", "pypi_json_response_empty.json"))
        stub_request(:get, registry_url).to_return(status: 200,
                                                   body: fixture("releases_api", "simple", "simple_index.html"))
      end

      it "falls back to HTML registry and fetches versions correctly" do
        result = fetch

        expect(result.releases).not_to be_empty
        expect(a_request(:get, json_url)).to have_been_made.once
        expect(a_request(:get, registry_url)).to have_been_made.once

        expect(result.releases.map(&:version)).to match_array(expected_releases.map(&:version))
      end
    end

    context "with an optional dependency postfix" do
      it "removes optional data from dependency name" do
        expect(fetcher.send(:remove_optional, "pyvista[io]")).to eq("pyvista")
        expect(fetcher.send(:remove_optional, "pyvista[example]")).to eq("pyvista")
        expect(fetcher.send(:remove_optional, "pyvista-example")).to eq("pyvista-example")
      end
    end
  end
end
