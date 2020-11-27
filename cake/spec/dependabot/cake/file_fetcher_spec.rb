# frozen_string_literal: true

require "spec_helper"
require "dependabot/cake/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Cake::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:directory) { "/" }
  let(:github_url) { "https://api.github.com/" }
  let(:url) { github_url + "repos/gocardless/bump/contents/" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  context "with a cake file" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_cake_file_repo.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "build.cake?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: cake_file_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    let(:cake_file_fixture) { fixture("github", "contents_cake_file.json") }

    it "fetches the cake file" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(build.cake))
    end

    context "that has an invalid encoding" do
      let(:cake_file_fixture) { fixture("github", "contents_image.json") }

      it "raises a helpful error" do
        expect { file_fetcher_instance.files }.
          to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end
  end

  context "with multiple cake files" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_cake_file_repo_multiple.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "build.cake?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: cake_file_fixture,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "tasks.cake?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: cake_file_2_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    let(:cake_file_fixture) { fixture("github", "contents_cake_file.json") }
    let(:cake_file_2_fixture) { fixture("github", "contents_cake_file.json") }

    it "fetches both cake files" do
      expect(file_fetcher_instance.files.count).to eq(2)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(build.cake tasks.cake))
    end

    context "one of which has an invalid encoding" do
      let(:cake_file_fixture) { fixture("github", "contents_image.json") }

      it "fetches the first cake file, and ignores the invalid one" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(tasks.cake))
      end
    end
  end

  context "with a directory that doesn't exist" do
    let(:directory) { "/nonexistent" }

    before do
      stub_request(:get, url + "nonexistent?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 404,
          body: fixture("github", "not_found.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "with a cake and config files" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_cake_file_repo_with_config_files.json"), # rubocop:disable Layout/LineLength
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "build.cake?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: cake_file_fixture,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "NuGet.Config?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: nuget_config_fixture,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "cake.config?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: cake_config_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    let(:cake_file_fixture) { fixture("github", "contents_cake_file.json") }
    let(:nuget_config_fixture) { fixture("github", "contents_nuget_config.json") } # rubocop:disable Layout/LineLength
    let(:cake_config_fixture) { fixture("github", "contents_cake_config.json") }

    it "fetches cake and config files" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(build.cake cake.config NuGet.Config))
    end
  end
end
