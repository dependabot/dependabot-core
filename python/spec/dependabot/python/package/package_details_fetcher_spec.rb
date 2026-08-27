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
          requirement: Dependabot::Python::Requirement.new(
            [">=2.7", "!=3.0.*", "!=3.1.*", "!=3.2.*", "!=3.3.*",
             "!=3.4.*", "!=3.5.*"]
          )
        )
      )
    ]
  end

  describe "#fetch" do
    subject(:fetch) { fetcher.fetch }

    context "with a private index" do
      let(:registry_base) { "https://registry.example.com/simple" }
      let(:json_url) { "https://registry.example.com/pypi/#{dependency_name}/json" }
      let(:dependency_files) do
        [Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: "--index-url #{registry_base}/\nrequests==2.4.1\n"
        )]
      end
      let(:simple_api_accept) do
        "application/vnd.pypi.simple.v1+json, " \
          "application/vnd.pypi.simple.v1+html;q=0.2, text/html;q=0.01"
      end

      context "when the index returns PEP 691 JSON" do
        let(:api_version) { "1.1" }
        let(:registry_request_url) { registry_url }

        before do
          stub_request(:get, registry_request_url)
            .with(headers: { "Accept" => simple_api_accept })
            .to_return(
              status: 200,
              headers: { "Content-Type" => "Application/Vnd.Pypi.Simple.V1+Json ; charset=utf-8" },
              body: JSON.dump(
                "meta" => { "api-version" => api_version },
                "name" => dependency_name,
                "files" => [
                  {
                    "filename" => "requests-2.32.3-py3-none-any.whl",
                    "url" => "../files/requests-2.32.3-py3-none-any.whl",
                    "requires-python" => ">=3.8",
                    "yanked" => false,
                    "upload-time" => "2026-08-24T12:34:56Z"
                  }
                ]
              )
            )
        end

        it "uses the negotiated JSON response without requesting the legacy JSON API" do
          result = fetch

          expect(result.releases.map { |release| release.version.to_s }).to eq(["2.32.3"])
          expect(result.releases.first.released_at).to eq(Time.utc(2026, 8, 24, 12, 34, 56))
          expect(result.releases.first.url)
            .to eq("https://registry.example.com/simple/files/requests-2.32.3-py3-none-any.whl")
          expect(a_request(:get, registry_url)).to have_been_made.once
          expect(a_request(:get, json_url)).not_to have_been_made
        end

        context "with an authenticated index" do
          let(:registry_base) { "https://user:pass@registry.example.com/simple" }
          let(:registry_request_url) { "https://registry.example.com/simple/#{dependency_name}/" }

          it "does not expose credentials in the release URL" do
            expect(fetch.releases.first.url)
              .to eq("https://registry.example.com/simple/files/requests-2.32.3-py3-none-any.whl")
          end
        end

        context "with an unsupported API major version" do
          let(:api_version) { "2.0" }

          it "rejects the response" do
            expect { fetch }
              .to raise_error(Dependabot::DependencyFileNotResolvable, "Unsupported PEP 691 API version: 2.0")
          end
        end
      end

      context "when the request times out" do
        before do
          stub_request(:get, registry_url).to_raise(Excon::Error::Timeout)
        end

        it "preserves the error without retrying as HTML" do
          expect { fetch }.to raise_error(Dependabot::PrivateSourceTimedOut)
          expect(
            a_request(:get, registry_url).with(headers: { "Accept" => "text/html" })
          ).not_to have_been_made
        end
      end

      context "when the index returns HTML" do
        before do
          stub_request(:get, registry_url)
            .with(headers: { "Accept" => simple_api_accept })
            .to_return(
              status: 200,
              headers: { "Content-Type" => "text/html" },
              body: fixture("releases_api", "simple", "simple_index.html")
            )
        end

        it "parses the negotiated HTML response without requesting the legacy JSON API" do
          result = fetch

          expect(result.releases.map(&:version)).to match_array(expected_releases.map(&:version))
          expect(a_request(:get, registry_url)).to have_been_made.once
          expect(a_request(:get, json_url)).not_to have_been_made
        end
      end
    end

    context "with a valid JSON response" do
      before do
        stub_request(:get, json_url).to_return(
          status: 200,
          body: fixture("releases_api", "pypi", "pypi_json_response.json")
        )
        stub_request(:get, registry_url).to_return(
          status: 200,
          body: fixture("releases_api", "simple", "simple_index.html")
        )
      end

      it "fetches data from JSON registry first and returns correct package releases" do
        result = fetch

        expect(result.releases).not_to be_empty
        expect(a_request(:get, json_url)).to have_been_made.once
        expect(a_request(:get, registry_url)).not_to have_been_made

        expect(result.releases.map(&:version)).to match_array(expected_releases.map(&:version))
      end

      context "with credentials for PyPI" do
        let(:credentials) do
          [Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://pypi.org/simple/",
              "token" => "user:pass",
              "replaces-base" => true
            }
          )]
        end

        it "retains the legacy JSON-first strategy" do
          fetch

          expect(a_request(:get, json_url)).to have_been_made.once
          expect(a_request(:get, registry_url)).not_to have_been_made
        end
      end
    end

    context "when JSON response is empty" do
      before do
        stub_request(:get, json_url).to_return(
          status: 200,
          body: fixture("releases_api", "pypi", "pypi_json_response_empty.json")
        )
        stub_request(:get, registry_url).to_return(
          status: 200,
          body: fixture("releases_api", "simple", "simple_index.html")
        )
      end

      it "falls back to HTML registry and fetches versions correctly" do
        result = fetch

        expect(result.releases).not_to be_empty
        expect(a_request(:get, json_url)).to have_been_made.once
        expect(a_request(:get, registry_url)).to have_been_made.once

        expect(result.releases.map(&:version)).to match_array(expected_releases.map(&:version))
      end
    end

    context "when JSON response contains a malformed version string" do
      let(:dependency_name) { "google-api-python-client" }
      let(:json_url) { "https://pypi.org/pypi/#{dependency_name}/json" }
      let(:registry_url) { "#{registry_base}/google-api-python-client/" }

      before do
        stub_request(:get, json_url).to_return(
          status: 200,
          body: fixture("releases_api", "pypi", "pypi_json_response_with_malformed_version.json")
        )
        stub_request(:get, registry_url).to_return(
          status: 200,
          body: fixture("releases_api", "simple", "simple_index.html")
        )
      end

      it "skips the malformed version but continues processing valid versions from JSON" do
        result = fetch

        expect(result.releases).not_to be_empty
        expect(a_request(:get, json_url)).to have_been_made.once
        # Should NOT fall back to HTML since we can process valid versions from JSON
        expect(a_request(:get, registry_url)).not_to have_been_made

        # Should have only the valid versions (2.184.0 and 2.185.0), not the malformed one
        version_strings = result.releases.map { |r| r.version.to_s }
        expect(version_strings).to include("2.184.0", "2.185.0")
        expect(version_strings).not_to include("1.0beta5prerelease")

        # Verify that valid versions retain their upload_time (released_at)
        release_version = result.releases.find { |r| r.version.to_s == "2.185.0" }
        expect(release_version).not_to be_nil
        expect(release_version.released_at).not_to be_nil
        expect(release_version.released_at).to be_a(Time)
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
