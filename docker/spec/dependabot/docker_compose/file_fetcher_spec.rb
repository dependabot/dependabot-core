# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker_compose/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::DockerCompose::FileFetcher do
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

  context "with a docker-compose.yml file" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_docker_repo.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "docker-compose.yml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: composefile_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    let(:composefile_fixture) do
      fixture("github", "contents_docker-compose.json")
    end

    it "fetches the docker-compose.yml file" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(docker-compose.yml))
    end

    context "that has an invalid encoding" do
      let(:composefile_fixture) { fixture("github", "contents_image.json") }

      it "raises a helpful error" do
        expect { file_fetcher_instance.files }.
          to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end
  end

  context "with docker-compose.yml override file" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_docker_repo_multiple.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "docker-compose.yml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: composefile_fixture,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "docker-compose.override.yml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: composefile_2_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    let(:composefile_fixture) do
      fixture("github", "contents_docker-compose.json")
    end
    let(:composefile_2_fixture) do
      fixture("github", "contents_docker-compose.json")
    end

    it "fetches both docker-compose.yml files" do
      expect(file_fetcher_instance.files.count).to eq(2)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(docker-compose.yml docker-compose.override.yml))
    end

    context "one of which has an invalid encoding" do
      let(:composefile_2_fixture) { fixture("github", "contents_image.json") }

      it "fetches the first docker-compose.yml file, "\
         "and ignores the invalid one" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(docker-compose.yml))
      end
    end
  end

  context "with a custom named docker-compose.yml file" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_docker_repo_custom.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "docker-compose.override.yml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_docker-compose.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the docker-compose.override.yml file" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(docker-compose.override.yml))
    end
  end

  context "with a directory that doesn't exist" do
    let(:directory) { "/non/existant" }

    before do
      stub_request(:get, url + "non/existant?ref=sha").
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
end
