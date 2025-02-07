# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/file_fetchers"
require "dependabot/bun"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Javascript::Bun::FileFetcher do
  let(:json_header) { { "content-type" => "application/json" } }
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end
  let(:directory) { "/" }
  let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end

  before do
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")

    stub_request(:get, File.join(url, "package.json?ref=sha"))
      .with(headers: { "Authorization" => "token token" })
      .to_return(
        status: 200,
        body: fixture("github", "package_json_content.json"),
        headers: json_header
      )
  end

  context "with a bun.lock but no package-lock.json file" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_js_bun.json"),
          headers: json_header
        )
      stub_request(:get, File.join(url, "package-lock.json?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 404)
      stub_request(:get, File.join(url, "bun.lock?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "bun_lock_content.json"),
          headers: json_header
        )
    end

    describe "fetching and parsing the bun.lock" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:enable_bun_ecosystem).and_return(enable_beta_ecosystems)
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:enable_beta_ecosystems).and_return(enable_beta_ecosystems)
      end

      context "when the experiment :enable_beta_ecosystems is inactive" do
        let(:enable_beta_ecosystems) { false }

        it "does not fetch or parse the the bun.lock" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(%w(package.json))
          expect(file_fetcher_instance.ecosystem_versions)
            .to match({ package_managers: { "unknown" => an_instance_of(Integer) } })
        end
      end

      context "when the experiment :enable_beta_ecosystems is active" do
        let(:enable_beta_ecosystems) { true }

        it "fetches and parses the bun.lock" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(%w(package.json bun.lock))
          expect(file_fetcher_instance.ecosystem_versions)
            .to match({ package_managers: { "bun" => an_instance_of(Integer) } })
        end
      end
    end
  end

  context "with a path dependency" do
    before do
      stub_request(:get, File.join(url, "package.json?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "package_json_with_path_content.json"),
          headers: json_header
        )
    end

    context "with a bad package.json" do
      before do
        stub_request(:get, File.join(url, "package.json?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "gemfile_content.json"),
            headers: json_header
          )
      end

      it "raises a DependencyFileNotParseable error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_name).to eq("package.json")
          end
      end
    end

    context "with a bad dependencies object" do
      before do
        stub_request(:get, File.join(url, "package.json?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "package_json_with_dependency_arrays.json"),
            headers: json_header
          )
      end

      it "raises a DependencyFileNotParseable error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_name).to eq("package.json")
          end
      end
    end

    context "when path is fetchable" do
      before do
        stub_request(:get, File.join(url, "deps/etag/package.json?ref=sha"))
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "package_json_content.json"),
            headers: json_header
          )
      end

      it "fetches package.json from path dependency" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name))
          .to include("deps/etag/package.json")
        path_file = file_fetcher_instance.files
                                         .find { |f| f.name == "deps/etag/package.json" }
        expect(path_file.support_file?).to be(true)
      end
    end
  end

  context "with package.json file just including a dummy string" do
    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, File.join(url, "package.json?ref=sha"))
        .to_return(
          status: 200,
          body: fixture_to_response("projects/javascript/package_json_faked", "package.json"),
          headers: json_header
        )
    end

    it "raises a DependencyFileNotParseable error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
          expect(error.file_name).to eq("package.json")
        end
    end
  end

  context "with packageManager field not in x.y.z format" do
    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, File.join(url, "package.json?ref=sha"))
        .to_return(
          status: 200,
          body: fixture_to_response("projects/javascript/package_manager_unparseable", "package.json"),
          headers: json_header
        )
    end

    it "still fetches package.json fine" do
      expect(file_fetcher_instance.files.count).to eq(1)
    end
  end

  context "with lockfileVersion not in integer format" do
    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, File.join(url, "package.json?ref=sha"))
        .to_return(
          status: 200,
          body: fixture_to_response("projects/javascript/lockfile_version_unparseable", "package.json"),
          headers: json_header
        )
    end

    it "still fetches files" do
      expect(file_fetcher_instance.files.count).to eq(1)
    end
  end
end

def fixture_to_response(dir, file)
  JSON.dump({ "content" => Base64.encode64(fixture(dir, file)) })
end
