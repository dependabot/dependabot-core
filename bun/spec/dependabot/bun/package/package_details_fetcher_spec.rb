# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bun/package/package_details_fetcher"
require "dependabot/bun/version"
require "dependabot/bun/requirement"
require "dependabot/package/package_release"
require "dependabot/package/package_language"

RSpec.describe Dependabot::Bun::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:dependency_name) { "react" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "16.6.0",
      requirements: [{
        requirement: "^16.0",
        file: "package.json",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "bun"
    )
  end

  let(:dependency_files) { [] }
  let(:credentials) { [] }
  let(:registry_url) { "https://registry.npmjs.org/#{dependency_name}" }

  describe "#fetch" do
    subject(:details) { fetcher.fetch }

    before do
      stub_request(:get, registry_url).to_return(
        status: 200,
        body: fixture("npm_responses", "react.json")
      )
    end

    context "when version field exists" do
      it "includes the requested version in the list" do
        expect(details.releases.map(&:version)).to include(Dependabot::Bun::Version.new("16.6.0"))
      end
    end

    context "when released_at field exists" do
      it "parses the correct release date" do
        release = details.releases.find { |r| r.version.to_s == "16.6.0" }
        expect(release.released_at).to eq(Time.parse("2018-10-23T23:36:06.553Z"))
      end
    end

    context "when version is deprecated" do
      it "marks it as deprecated and includes a reason" do
        release = details.releases.find { |r| r.version.to_s == "0.7.1" }
        expect(release.details["deprecated"]).to be_a(String)
      end
    end

    context "when version is not deprecated" do
      it "is not marked as yanked and has no reason" do
        release = details.releases.find { |r| r.version.to_s == "16.6.0" }
        expect(release.yanked).to be(false)
        expect(release.yanked_reason).to be_nil
      end
    end

    it "includes the correct version URL" do
      release = details.releases.find { |r| r.version.to_s == "16.6.0" }
      expect(release.url).to include("/react/v/16.6.0")
    end

    context "when version includes a node engine" do
      it "includes the node language with requirement" do
        release = details.releases.find { |r| r.version.to_s == "16.6.0" }
        expect(release.language&.name).to eq("node")
        expect(release.language&.requirement.to_s).to eq(">= 0.10.0")
      end
    end

    context "when package_type field is defined" do
      it "parses the repository type" do
        release = details.releases.find { |r| r.version.to_s == "16.6.0" }
        expect(release.package_type).to eq("git")
      end
    end

    context "when version is the latest" do
      it "sets latest to true" do
        latest_version = details.releases.find(&:latest)
        expect(latest_version.version.to_s).to eq("16.6.0")
      end
    end

    context "when version is not the latest" do
      it "sets latest to false" do
        release = details.releases.find { |r| r.version.to_s == "16.5.0" }
        expect(release.latest).to be(false)
      end
    end

    context "when known metadata fields are missing" do
      before do
        stub_request(:get, registry_url).to_return(
          status: 200,
          body: JSON.dump("name" => dependency_name)
        )
      end

      it "returns no releases or dist-tags" do
        expect(details.releases).to eq([])
        expect(details.dist_tags).to be_nil
      end
    end

    context "when successful JSON has the wrong top-level shape" do
      before do
        stub_request(:get, registry_url).to_return(status: 200, body: "[]")
      end

      it "raises at the metadata boundary" do
        expect { details }.to raise_error(TypeError, "npm registry package must be an object")
      end
    end

    context "when a release entry has the wrong shape" do
      before do
        stub_request(:get, registry_url).to_return(
          status: 200,
          body: JSON.dump("versions" => { "1.0.0" => "invalid" })
        )
      end

      it "raises at the release boundary" do
        expect { details }.to raise_error(TypeError, "version 1.0.0 details must be an object")
      end
    end

    context "when a version key is not valid semantic versioning" do
      before do
        stub_request(:get, registry_url).to_return(
          status: 200,
          body: JSON.dump("versions" => { "not-a-version" => { "custom" => { "nested" => true } } })
        )
      end

      it "skips the release" do
        expect(details.releases).to eq([])
      end
    end

    [
      ["time", { "versions" => { "1.0.0" => {} }, "time" => { "1.0.0" => 1 } }],
      ["dist-tags", { "dist-tags" => { "latest" => 1 } }],
      ["engines", { "versions" => { "1.0.0" => { "engines" => "invalid" } } }],
      ["repository", { "versions" => { "1.0.0" => { "repository" => 1 } } }]
    ].each do |field, response_body|
      context "when #{field} has the wrong shape" do
        before do
          stub_request(:get, registry_url).to_return(status: 200, body: JSON.dump(response_body))
        end

        it "raises at the metadata boundary" do
          expect { details }.to raise_error(TypeError)
        end
      end
    end

    context "when a release timestamp is invalid" do
      before do
        stub_request(:get, registry_url).to_return(
          status: 200,
          body: JSON.dump(
            "versions" => { "1.0.0" => {} },
            "time" => { "1.0.0" => "invalid" }
          )
        )
      end

      it "preserves the timestamp parsing failure" do
        expect { details }.to raise_error(ArgumentError)
      end
    end

    context "with a git dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "16.6.0",
          requirements: [{
            requirement: nil,
            file: "package.json",
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/facebook/react",
              ref: "v16.6.0"
            }
          }],
          package_manager: "bun"
        )
      end

      context "when the registry returns invalid JSON" do
        before do
          stub_request(:get, registry_url).to_return(status: 200, body: "{")
        end

        it "keeps the existing empty-result fallback" do
          expect(details.releases).to eq([])
          expect(details.dist_tags).to be_nil
        end
      end

      context "when the registry returns wrong-shaped valid JSON" do
        before do
          stub_request(:get, registry_url).to_return(status: 200, body: "[]")
        end

        it "raises at the metadata boundary" do
          expect { details }.to raise_error(TypeError, "npm registry package must be an object")
        end
      end
    end

    context "when the registry raises Excon::Error::Socket" do
      context "with a private registry" do
        let(:registry_url) { "https://npm.fury.io/dependabot/react" }

        before do
          stub_request(:get, registry_url)
            .to_raise(Excon::Error::Socket.new(EOFError.new))
          allow_any_instance_of(described_class) # rubocop:disable RSpec/AnyInstance
            .to receive(:dependency_registry).and_return("npm.fury.io/dependabot")
          allow_any_instance_of(described_class) # rubocop:disable RSpec/AnyInstance
            .to receive(:dependency_url).and_return(registry_url)
        end

        it "raises PrivateSourceTimedOut" do
          expect { fetcher.fetch }
            .to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
              expect(error.source).to eq("npm.fury.io/<redacted>")
            end
        end
      end

      context "with the global registry" do
        before do
          stub_request(:get, registry_url)
            .to_raise(Excon::Error::Socket.new(EOFError.new))
        end

        it "re-raises the Excon::Error::Socket" do
          expect { fetcher.fetch }.to raise_error(Excon::Error::Socket)
        end
      end
    end
  end
end
