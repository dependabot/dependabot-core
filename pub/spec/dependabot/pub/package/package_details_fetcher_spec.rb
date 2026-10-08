# typed: false
# frozen_string_literal: true

require "json"
require "time"
require "excon"
require "nokogiri"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/pub"
require "dependabot/package/package_release"
require "dependabot/package/package_details"
require "dependabot/pub/helpers"
require "dependabot/requirements_update_strategy"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/version_filters"
require "spec_helper"

RSpec.describe Dependabot::Pub::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      options: options
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "pub"
    )
  end

  let(:requirements) { [] }
  let(:dependency_name) { "lints" }
  let(:requirements_update_strategy) { nil }
  let(:dependency_version) { "0.1.0" }

  let(:dependency_files) { [] }
  let(:credentials) { [] }
  let(:options) { {} }
  let(:registry_url) { "https://pub.dev/api/packages/#{dependency_name}" }

  describe "#report" do
    let(:dependency_files) do
      [Dependabot::DependencyFile.new(name: "pubspec.yaml", content: "name: report_cache_test\n")]
    end
    let(:entry) do
      {
        "name" => dependency_name,
        "version" => dependency_version,
        "latest" => "2.0.0",
        "compatible" => [],
        "singleBreaking" => [],
        "multiBreaking" => [],
        "unknown" => { "keep" => [nil, false] }
      }
    end
    let(:report_body) { JSON.dump("dependencies" => [entry]) }
    let(:helper_status) { instance_double(Process::Status, success?: true) }
    let(:cache_file) do
      hash = Digest::SHA256.hexdigest(dependency_files.map { |file| "#{file.path}\n#{file.content}\n" }.join)
      "/tmp/report-#{hash}-pid-#{Process.pid}.json"
    end

    before do
      FileUtils.rm_f(cache_file)
      allow(Open3).to receive(:capture3).and_call_original
      allow(Open3).to receive(:capture3).with({}, "git", any_args).and_return(["", "", helper_status])
      allow(Open3).to receive(:capture3)
        .with({}, File.join(Dependabot::Pub::Helpers.pub_helpers_path, "infer_sdk_versions"), "", anything)
        .and_return([JSON.dump("flutter" => "3.24.1", "dart" => "3.5.1", "channel" => "stable"), "", helper_status])
      allow(Open3).to receive(:capture3)
        .with({}, "/tmp/flutter/bin/flutter", "doctor", anything).and_return(["", "", helper_status])
      allow(Open3).to receive(:capture3)
        .with({}, "/tmp/flutter/bin/flutter", "--version", "--machine", anything)
        .and_return([JSON.dump("frameworkVersion" => "3.24.1", "dartSdkVersion" => "3.5.1 (stable)"), "",
                     helper_status])
      allow(Open3).to receive(:capture3)
        .with(anything, File.join(Dependabot::Pub::Helpers.pub_helpers_path, "dependency_services"), "report", anything)
        .and_return([report_body, "", helper_status])
    end

    after { FileUtils.rm_f(cache_file) }

    it "writes the validated wire array and returns typed reports on cache hits" do
      expect(fetcher.report.first).to have_attributes(name: dependency_name, latest: "2.0.0")
      expect(JSON.parse(File.read(cache_file))).to eq([entry])

      cached_fetcher = described_class.new(dependency: dependency, dependency_files: dependency_files, credentials: [])
      expect(cached_fetcher.report.first).to have_attributes(name: dependency_name, latest: "2.0.0")
      expect(Open3).to have_received(:capture3)
        .with(anything,
              File.join(
                Dependabot::Pub::Helpers.pub_helpers_path,
                "dependency_services"
              ),
              "report",
              anything).once
    end

    context "with a malformed live response" do
      let(:report_body) { JSON.dump("dependencies" => [entry, nil]) }

      it "does not cache a partially parsed report" do
        expect { fetcher.report }.to raise_error(
          Dependabot::SharedHelpers::HelperSubprocessFailed, /report.dependencies\[1\] must be an object/
        )
        expect(File.exist?(cache_file)).to be(false)
      end
    end

    context "with a malformed cached response" do
      before { File.write(cache_file, JSON.dump([entry.merge("compatible" => false)])) }

      it "reports the invalid cache without running the helper or replacing the file" do
        cached_content = File.read(cache_file)
        expect { fetcher.report }.to raise_error(
          Dependabot::SharedHelpers::HelperSubprocessFailed, /report cache\[0\].compatible must be an array/
        )
        expect(Open3).not_to have_received(:capture3)
        expect(File.read(cache_file)).to eq(cached_content)
      end
    end

    context "when Flutter returns malformed machine output" do
      before do
        allow(Open3).to receive(:capture3)
          .with({}, "/tmp/flutter/bin/flutter", "--version", "--machine", anything)
          .and_return([JSON.dump("frameworkVersion" => "3.24.1", "dartSdkVersion" => []), "", helper_status])
      end

      it "does not generate or cache a report with an invalid SDK" do
        expect { fetcher.report }.to raise_error(
          Dependabot::SharedHelpers::HelperSubprocessFailed, /flutter --version.dartSdkVersion must be a string/
        )
        expect(File.exist?(cache_file)).to be(false)
        expect(Open3).not_to have_received(:capture3)
          .with(anything,
                File.join(
                  Dependabot::Pub::Helpers.pub_helpers_path,
                  "dependency_services"
                ),
                "report",
                anything)
      end
    end

    context "with an invalid known option" do
      let(:options) { { flutter_releases_url: 42 } }

      it "reports the input type without treating it as malformed helper output" do
        expect { fetcher.report }.to raise_error(TypeError, "Pub option flutter_releases_url must be a string or nil")
        expect(File.exist?(cache_file)).to be(false)
        expect(Open3).not_to have_received(:capture3)
      end
    end

    %i(pub_hosted_url flutter_releases_url).each do |key|
      context "with false #{key}" do
        let(:options) { { key => false } }

        it "rejects the option without generating or caching a report" do
          expect { fetcher.report }.to raise_error(TypeError, "Pub option #{key} must be a string or nil")
          expect(File.exist?(cache_file)).to be(false)
          expect(Open3).not_to have_received(:capture3)
            .with(anything,
                  File.join(Dependabot::Pub::Helpers.pub_helpers_path, "dependency_services"),
                  "report",
                  anything)
        end
      end
    end

    context "with nil URL options" do
      let(:options) { { pub_hosted_url: nil, flutter_releases_url: nil } }

      it "uses the default URLs" do
        expect(fetcher.report.first.name).to eq(dependency_name)
        expect(Open3).to have_received(:capture3)
          .with(hash_excluding("PUB_HOSTED_URL"),
                File.join(Dependabot::Pub::Helpers.pub_helpers_path, "dependency_services"),
                "report",
                anything)
      end
    end

    context "with an unknown option" do
      let(:options) { { extra_configuration: { enabled: true } } }

      it "preserves the shared options interface" do
        expect(fetcher.report.first.name).to eq(dependency_name)
      end
    end
  end

  describe "#package_details_metadata" do
    context "with packagedetailsfetcher" do
      before do
        stub_request(:get, registry_url).to_return(
          status: 200,
          body: fixture("pub_dev_responses/simple/lints.json")
        )
      end

      it "fetches package details metadata" do
        package_releases = fetcher.package_details_metadata

        package_release = package_releases.first

        expect(package_releases).to be_an(Array)

        expect(package_release.version).to eq(Gem::Version.new("0.1.0"))
        expect(package_release.released_at).to eq(Time.parse("2021-04-27 10:40:00.45138 UTC"))
      end

      context "with a path-prefixed registry URL ending in a slash" do
        let(:registry_url) { "https://registry.example.com/repository/pub/api/packages/#{dependency_name}" }
        let(:requirements) do
          [{
            file: "pubspec.yaml",
            requirement: "any",
            groups: [],
            source: {
              "description" => {
                "name" => dependency_name,
                "url" => "https://registry.example.com/repository/pub/"
              },
              "type" => "hosted"
            }
          }]
        end

        it "fetches package details using a single path separator" do
          expect(fetcher.package_details_metadata).not_to be_empty
          expect(WebMock).to have_requested(:get, registry_url).once
        end
      end
    end

    context "when the registry returns a server error" do
      before do
        stub_request(:get, registry_url).to_return(status: 503, body: "")
      end

      it "returns an empty list rather than partial metadata" do
        expect(fetcher.package_details_metadata).to eq([])
      end
    end

    context "when the response body is not valid JSON" do
      before do
        stub_request(:get, registry_url).to_return(status: 200, body: "not json")
      end

      it "returns an empty list rather than partial metadata" do
        expect(fetcher.package_details_metadata).to eq([])
      end
    end

    context "when a later release has an unparseable publish date" do
      before do
        body = {
          "name" => dependency_name,
          "versions" => [
            { "version" => "1.0.0", "published" => "2021-04-27T10:40:00.000Z" },
            { "version" => "1.1.0", "published" => "not-a-date" }
          ]
        }.to_json
        stub_request(:get, registry_url).to_return(status: 200, body: body)
      end

      it "discards the partial result instead of returning the releases parsed so far" do
        expect(fetcher.package_details_metadata).to eq([])
      end
    end
  end
end
