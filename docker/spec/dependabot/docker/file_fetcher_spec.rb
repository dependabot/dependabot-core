# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Docker::FileFetcher do
  def fixture(*name)
    File.read(File.join("spec", "fixtures", *name))
  end

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

  context "with a Dockerfile" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_docker_repo.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "Dockerfile?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: dockerfile_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    let(:dockerfile_fixture) { fixture("github", "contents_dockerfile.json") }

    it "fetches the Dockerfile" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Dockerfile))
    end

    context "that has an invalid encoding" do
      let(:dockerfile_fixture) { fixture("github", "contents_image.json") }

      it "raises a helpful error" do
        expect { file_fetcher_instance.files }.
          to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end
  end

  context "with multiple Dockerfiles" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_docker_repo_multiple.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "Dockerfile?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: dockerfile_fixture,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "Dockerfile-base?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: dockerfile_2_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    let(:dockerfile_fixture) { fixture("github", "contents_dockerfile.json") }
    let(:dockerfile_2_fixture) { fixture("github", "contents_dockerfile.json") }

    it "fetches both Dockerfiles" do
      expect(file_fetcher_instance.files.count).to eq(2)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Dockerfile Dockerfile-base))
    end

    context "one of which has an invalid encoding" do
      let(:dockerfile_2_fixture) { fixture("github", "contents_image.json") }

      it "fetches the first Dockerfile, and ignores the invalid one" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(Dockerfile))
      end
    end
  end

  context "with a custom named Dockerfile" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_docker_repo_custom.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "Dockerfile-base?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_dockerfile.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the Dockerfile" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Dockerfile-base))
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

  let(:token) { { "Authorization" => "token token" } }
  let(:json_content_type) { { "content-type" => "application/json" } }

  context "with a yml template", :pix4d do
    let(:file_fixture) { fixture("github", "contents_pipeline.json") }

    it_behaves_like "a dependency file fetcher"
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: token).
        to_return(
          status: 200,
          body: fixture("github", "contents_pipeline_repo.json"),
          headers: json_content_type
        )

      stub_request(:get, File.join(url, "pipeline-template.yml?ref=sha")).
        with(headers: token).
        to_return(
          status: 200,
          body: file_fixture,
          headers: json_content_type
        )
    end

    it "fetches the pipeline template" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w[pipeline-template.yml])
    end

    context "that has an invalid encoding" do
      let(:file_fixture) { fixture("github", "contents_image.json") }

      it "raises a helpful error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end
  end

  context "with multiple template files", :pix4d do
    it_behaves_like "a dependency file fetcher"
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: token)
        .to_return(
          status: 200,
          body: fixture("github", "contents_pipeline_repo_multiple.json"),
          headers: json_content_type
        )
      stub_request(:get, File.join(url, "pipeline-template.yml?ref=sha"))
        .with(headers: token)
        .to_return(
          status: 200,
          body: file_fixture,
          headers: json_content_type
        )
      stub_request(:get, File.join(url, "pipeline-template-base.yml?ref=sha"))
        .with(headers: token)
        .to_return(
          status: 200,
          body: file_2_fixture,
          headers: json_content_type
        )
    end

    let(:file_fixture) { fixture("github", "contents_pipeline.json") }
    let(:file_2_fixture) { fixture("github", "contents_pipeline.json") }

    it "fetches both template files" do
      expect(file_fetcher_instance.files.count).to eq(2)
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w[pipeline-template.yml pipeline-template-base.yml])
    end

    context "one of which has an invalid encoding" do
      let(:file_2_fixture) { fixture("github", "contents_image.json") }

      it "fetches the first file, and ignores the invalid one" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(%w[pipeline-template.yml])
      end
    end
  end

  context "with a custom named template file", :pix4d do
    it_behaves_like "a dependency file fetcher"
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: token)
        .to_return(
          status: 200,
          body: fixture("github", "contents_pipeline_repo_custom.json"),
          headers: json_content_type
        )

      stub_request(:get, File.join(url, "pipeline-template-base.yml?ref=sha"))
        .with(headers: token)
        .to_return(
          status: 200,
          body: fixture("github", "contents_pipeline.json"),
          headers: json_content_type
        )
    end

    it "fetches the template file" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w[pipeline-template-base.yml])
    end
  end

  context "with a directory that does not exist", :pix4d do
    it_behaves_like "a dependency file fetcher"
    let(:directory) { "/non/existant" }

    before do
      stub_request(:get, url + "non/existant?ref=sha")
        .with(headers: token)
        .to_return(
          status: 404,
          body: fixture("github", "not_found.json"),
          headers: json_content_type
        )
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "with a docker-image-version file", :pix4d do
    it_behaves_like "a dependency file fetcher"
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: token)
        .to_return(
          status: 200,
          body: '[{"name": "docker-image-version.yml","type": "file"}]',
          headers: json_content_type
        )

      stub_request(:get, File.join(url, "docker-image-version.yml?ref=sha"))
        .with(headers: token)
        .to_return(
          status: 200,
          body: '{
            "content": "RlJPTSB1YnVudHU6MTguMDQKCiMjIyBTWVNURU0gREVQRU5ERU5DSUVTCgoj\n",
            "encoding": "base64"
            }',
          headers: json_content_type
        )
    end

    it "fetches the template file" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w[docker-image-version.yml])
    end
  end
end
