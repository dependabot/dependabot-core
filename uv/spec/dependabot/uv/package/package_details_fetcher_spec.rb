# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/uv"
require "dependabot/uv/package"

RSpec.describe Dependabot::Uv::Package::PackageDetailsFetcher do
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
      package_manager: "uv"
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
        version: Dependabot::Uv::Version.new("2.32.3"),
        released_at: nil,
        yanked: false,
        yanked_reason: nil,
        downloads: -1,
        url: "https://files.pythonhosted.org/packages/f9/9b/335f9764261e915ed497fcdeb11df5dfd6f7bf257d4a6a2a686d80da4d54/requests-2.32.3-py3-none-any.whl",
        package_type: nil,
        language: Dependabot::Package::PackageLanguage.new(
          name: "python",
          version: nil,
          requirement: Dependabot::Uv::Requirement.new([">=3.8"])
        )
      ),
      Dependabot::Package::PackageRelease.new(
        version: Dependabot::Uv::Version.new("2.27.0"),
        released_at: nil,
        yanked: false,
        yanked_reason: nil,
        downloads: -1,
        url: "https://files.pythonhosted.org/packages/47/01/f420e7add78110940639a958e5af0e3f8e07a8a8b62049bac55ee117aa91/requests-2.27.0-py2.py3-none-any.whl",
        package_type: nil,
        language: Dependabot::Package::PackageLanguage.new(
          name: "python",
          version: nil,
          requirement: Dependabot::Uv::Requirement.new(
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
              headers: { "Content-Type" => "application/vnd.pypi.simple.v1+json" },
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

    context "with typed PyPI distributions" do
      let(:body) do
        JSON.generate(
          "releases" => { "1.0.0" => [
            { "url" => "first.tar.gz", "yanked" => false },
            { "url" => "last.whl", "yanked" => true, "yanked_reason" => "Broken", "requires_python" => ">=3.8" }
          ] }
        )
      end

      before { stub_request(:get, json_url).to_return(status: 200, body: body) }

      it "uses Python's last-file policy and preserves its typed metadata" do
        expect(fetch.releases.length).to eq(1)
        expect(fetch.releases.first).to have_attributes(url: "last.whl", yanked: true, yanked_reason: "Broken")
        expect(fetch.releases.first.language.requirement.to_s).to eq(">= 3.8")
      end

      context "with malformed earlier metadata" do
        let(:body) { '{"releases":{"1.0.0":[{"yanked":1},{}]}}' }

        it "does not hide the error through HTML fallback" do
          expect { fetch }.to raise_error(Dependabot::DependencyFileNotResolvable)
          expect(a_request(:get, registry_url)).not_to have_been_made
        end
      end
    end

    context "with typed private distributions" do
      let(:registry_base) { "https://uv-index.example.test/simple" }
      let(:dependency_files) do
        [Dependabot::DependencyFile.new(
          name: "requirements.txt", content: "--index-url #{registry_base}/\nrequests==2.4.1\n"
        )]
      end
      let(:response_type) { "application/vnd.pypi.simple.v1+json" }
      let(:body) do
        JSON.generate(
          "files" => [
            { "filename" => "requests-1.0.0.tar.gz", "url" => "first.tar.gz" },
            { "filename" => "requests-1.0.0.whl", "url" => "last.whl", "yanked" => "Broken" }
          ]
        )
      end

      before do
        stub_request(:get, registry_url).to_return(
          status: 200,
          headers: { "Content-Type" => response_type },
          body: body
        )
      end

      it "retains every Simple JSON distribution" do
        expect(fetch.releases.map(&:url)).to contain_exactly("#{registry_url}first.tar.gz", "#{registry_url}last.whl")
        expect(fetch.releases.map(&:yanked)).to contain_exactly(false, true)
      end

      context "with malformed Simple JSON" do
        let(:body) { "not JSON" }

        it "raises instead of returning no releases" do
          expect { fetch }.to raise_error(Dependabot::DependencyFileNotResolvable, /Simple API JSON/)
        end
      end

      context "with HTML" do
        let(:response_type) { "text/html" }
        let(:body) do
          '<a href="first.tar.gz">requests-1.0.0.tar.gz</a>' \
            '<a href="last.whl#sha256=abc" data-yanked="Broken" data-requires-python="&gt;=3.8">requests-1.0.0.whl</a>'
        end

        it "uses resolved hrefs and actual withdrawal attributes for the selected file" do
          expect(fetch.releases.length).to eq(1)
          expect(fetch.releases.first).to have_attributes(
            url: "#{registry_url}last.whl#sha256=abc", yanked: true, yanked_reason: "Broken"
          )
          expect(fetch.releases.first.language.requirement.to_s).to eq(">= 3.8")
        end
      end
    end
  end
end
