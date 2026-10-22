# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/security_advisory"
require "dependabot/composer/package_manager"
require "dependabot/composer/package/package_details_fetcher"

RSpec.describe Dependabot::Composer::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      dependency_files: files,
      credentials: credentials,
      ignored_versions: [],
      security_advisories: []
    )
  end

  let(:dependency_name) { "illuminate/support" }
  let(:dependency_files) { [] }
  let(:files) { project_dependency_files(project_name) }
  let(:credentials) { [] }
  let(:json_url) { "https://repo.packagist.org/p2/#{dependency_name}.json" }
  let(:project_name) { "package_details_fetcher" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "12.14.1",
      requirements: [{
        requirement: "==12.14.1",
        file: "composer.json",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "composer"
    )
  end

  let(:latest_release) do
    Dependabot::Package::PackageRelease.new(
      version: Dependabot::Composer::Version.new("12.14.1"),
      released_at: Time.parse("2025-05-13T15:08:45+00:00"),
      yanked: false,
      url: "https://api.github.com/repos/illuminate/support/zipball/e7789d3fd90493d076318df934a92d687e4bc340",
      package_type: described_class::PACKAGE_TYPE,
      language: Dependabot::Package::PackageLanguage.new(
        name: "php",
        version: nil
      )
    )
  end

  describe "registry release flow" do
    let(:first_url) { "https://first.example.test/packages.json" }
    let(:second_url) { "https://second.example.test/packages.json" }
    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "composer.json",
          content: JSON.generate(
            "repositories" => [
              { "type" => "composer", "url" => "https://first.example.test" },
              { "type" => "composer", "url" => "https://second.example.test" },
              { "packagist.org" => false }
            ]
          )
        )
      ]
    end
    let(:first_entries) do
      [
        { "version" => "v2.0.0", "time" => "2024-04-02T00:00:00Z",
          "dist" => { "url" => "https://first.example.test/2.zip" } },
        { "version" => "v1.0.0", "time" => "2024-01-01T00:00:00Z",
          "dist" => { "url" => "https://first.example.test/1.zip" } },
        { "version" => nil }
      ]
    end
    let(:second_entries) do
      [
        { "version" => "v2.0.0", "dist" => { "url" => "https://second.example.test/2.zip" } },
        { "version" => "1.0.0", "dist" => { "url" => "https://second.example.test/1.zip" } },
        { "version" => "not a version" }
      ]
    end
    let(:first_body) { JSON.generate("packages" => { dependency_name => first_entries }) }
    let(:second_body) { JSON.generate("packages" => { dependency_name => second_entries }) }

    before do
      stub_request(:get, first_url).to_return(status: 200, body: first_body)
      stub_request(:get, second_url).to_return(status: 200, body: second_body)
    end

    it "preserves both duplicate-precedence stages and shares a complete cache across fetch methods" do
      releases = fetcher.fetch_releases
      expect(releases.map { |release| release.version.to_s }).to eq(%w(2.0.0 1.0.0 1.0.0))
      expect(releases.map(&:url)).to eq(
        ["https://first.example.test/2.zip", "https://first.example.test/1.zip", "https://second.example.test/1.zip"]
      )
      expect(fetcher.fetch.releases.map(&:url)).to eq(
        ["https://first.example.test/2.zip", "https://second.example.test/1.zip"]
      )
      expect(a_request(:get, first_url)).to have_been_made.once
      expect(a_request(:get, second_url)).to have_been_made.once
      expect(a_request(:get, json_url)).not_to have_been_made
    end

    context "with a legacy version map" do
      let(:first_body) do
        versions = first_entries.each_with_index.to_h { |entry, i| ["key#{i}", entry] }
        JSON.generate("packages" => { dependency_name => versions })
      end
      let(:second_entries) { [] }

      it "reads versions from the records rather than the map keys" do
        expect(fetcher.fetch_releases.map { |release| release.version.to_s }).to eq(%w(2.0.0 1.0.0))
      end
    end

    context "with empty registries" do
      let(:first_entries) { [] }
      let(:second_entries) { [] }

      it "caches an empty successful collection" do
        expect(fetcher.fetch.releases).to eq([])
        expect(fetcher.fetch_releases).to eq([])
        expect(a_request(:get, first_url)).to have_been_made.once
        expect(a_request(:get, second_url)).to have_been_made.once
      end
    end

    %i(fetch fetch_releases).each do |method|
      context "when using #{method}" do
        context "with minified metadata" do
          let(:first_entries) { [super().first, { "version" => "1.0.0" }] }
          let(:first_body) do
            JSON.generate("minified" => "composer/2.0", "packages" => { dependency_name => first_entries })
          end
          let(:second_entries) { [] }

          it "restores inherited dates and URLs before release construction" do
            result = fetcher.public_send(method)
            releases = method == :fetch ? result.releases : result
            expect(releases.map(&:released_at)).to eq([Time.utc(2024, 4, 2)] * 2)
            expect(releases.map(&:url)).to eq(Array.new(2, "https://first.example.test/2.zip"))
          end
        end

        context "when a later registry returns malformed JSON" do
          let(:second_body) { '{"do-not-echo-this":' }

          it "does not cache partial data and retries the collection after the response is repaired" do
            expect { fetcher.public_send(method) }.to raise_error(Dependabot::DependencyFileNotResolvable)

            repaired_body = JSON.generate("packages" => { dependency_name => [{ "version" => "3.0.0" }] })
            stub_request(:get, second_url).to_return(status: 200, body: repaired_body)
            expect(fetcher.fetch_releases.map { |release| release.version.to_s }).to eq(%w(2.0.0 1.0.0 3.0.0))
            expect(a_request(:get, first_url)).to have_been_made.twice
            expect(a_request(:get, second_url)).to have_been_made.twice
          end
        end

        context "with a malformed duplicate at a later registry" do
          let(:second_entries) { [{ "version" => "v2.0.0", "time" => false }] }

          it "does not hide the malformed entry behind an earlier valid version" do
            expect { fetcher.public_send(method) }.to raise_error(
              Dependabot::DependencyFileNotResolvable, /second\.example\.test.*releases\[0\]\.time/
            )
          end
        end

        context "with a malformed trailing record at a later registry" do
          let(:second_entries) { [{ "version" => "3.0.0" }, { "version" => "4.0.0", "time" => false }] }

          it "retries all sources after repairing the invalid metadata" do
            expect { fetcher.public_send(method) }.to raise_error(
              Dependabot::DependencyFileNotResolvable, /releases\[1\]\.time/
            )

            repaired_body = JSON.generate("packages" => { dependency_name => [{ "version" => "4.0.0" }] })
            stub_request(:get, second_url).to_return(status: 200, body: repaired_body)
            expect(fetcher.fetch_releases.map { |release| release.version.to_s }).to eq(%w(2.0.0 1.0.0 4.0.0))
            expect(a_request(:get, first_url)).to have_been_made.twice
            expect(a_request(:get, second_url)).to have_been_made.twice
          end
        end

        context "with malformed metadata on an unsupported version" do
          let(:first_entries) { [{ "version" => "not a version", "dist" => false }] }

          it "validates before version filtering" do
            expect { fetcher.public_send(method) }.to raise_error(
              Dependabot::DependencyFileNotResolvable, /releases\[0\]\.dist/
            )
          end
        end
      end
    end

    [401, 403, 404, 500].each do |status|
      context "when a registry returns HTTP #{status}" do
        let(:second_entries) { [] }

        before { stub_request(:get, first_url).to_return(status: status, body: "not JSON") }

        it "preserves the empty-source behavior without decoding the error body" do
          expect(fetcher.fetch_releases).to eq([])
        end
      end
    end

    [Excon::Error::Socket, Excon::Error::Timeout].each do |error_class|
      context "when a registry raises #{error_class}" do
        let(:second_entries) { [] }

        before do
          allow(Dependabot::RegistryClient).to receive(:get).and_call_original
          allow(Dependabot::RegistryClient).to receive(:get)
            .with(url: first_url, options: anything).and_raise(error_class)
        end

        it "preserves the empty-source fallback" do
          expect(fetcher.fetch_releases).to eq([])
        end
      end
    end

    ["null", "[]", "{}", '{"packages":[]}'].each do |body|
      context "with a legacy empty response #{body}" do
        let(:first_body) { body }
        let(:second_entries) { [] }

        it "returns no releases through the public fetcher" do
          expect(fetcher.fetch.releases).to eq([])
        end
      end
    end
  end

  describe "#fetch" do
    subject(:fetch) { fetcher.fetch }

    context "with a valid response" do
      before do
        stub_request(:get, json_url)
          .to_return(
            status: 200,
            body: fixture("packagist_responses", "illuminate-support-response.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns the package details" do
        expect(fetch).to be_a(Dependabot::Package::PackageDetails)
        expect(fetch.releases).not_to be_empty
        expect(a_request(:get, json_url)).to have_been_made.once

        expect(fetch.releases.size).to be(894)

        first_result = fetch.releases.first
        expect(first_result.version).to eq(latest_release.version)
        expect(first_result.released_at).to eq(latest_release.released_at)
        expect(first_result.url).to eq(latest_release.url)
        expect(first_result.package_type).to eq(latest_release.package_type)
      end
    end

    context "with VCS credentials missing registry field" do
      let(:project_name) { "package_details_fetcher_with_vcs" }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "git_source",
              "host" => "github.com"
            }
          ),
          Dependabot::Credential.new(
            {
              "type" => "composer_repository",
              "registry" => "github.com",
              "username" => "x-access-token",
              "password" => "token123"
            }
          ),
          Dependabot::Credential.new(
            {
              "type" => "composer_repository",
              "url" => "git@github.com:org/private-package.git",
              "replaces-base" => false
            }
          )
        ]
      end

      before do
        stub_request(:get, json_url)
          .to_return(
            status: 200,
            body: fixture("packagist_responses", "illuminate-support-response.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "does not raise an error" do
        package_details = nil

        expect { package_details = fetch }.not_to raise_error
        expect(package_details).to be_a(Dependabot::Package::PackageDetails)
        expect(package_details.releases).not_to be_empty
      end
    end
  end
end
