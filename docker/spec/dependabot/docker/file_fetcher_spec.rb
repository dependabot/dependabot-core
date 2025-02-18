# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Docker::FileFetcher do
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:url) { github_url + "repos/gocardless/bump/contents/" }
  let(:github_url) { "https://api.github.com/" }
  let(:directory) { "/" }
  let(:file_fetcher_instance) do
    described_class.new(
      source: source,
      credentials: credentials,
      repo_contents_path: nil
    )
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end

  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  context "with no Dockerfile or Kubernetes YAML file" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_no_docker_repo.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises the expected error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "with a Dockerfile" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_docker_repo.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "Dockerfile?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: dockerfile_fixture,
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "docker-compose.yml?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: dockerfile_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    let(:dockerfile_fixture) do
      fixture("github", "contents_dockerfile.json")
    end

    it "fetches the Dockerfile" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(Dockerfile))
    end

    context "when an invalid encoding is present" do
      let(:dockerfile_fixture) { fixture("github", "contents_image.json") }

      it "raises a helpful error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end
  end

  context "with multiple Dockerfiles" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_docker_repo_multiple.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "Dockerfile?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: dockerfile_fixture,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "Dockerfile-base?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: dockerfile_2_fixture,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "Containerfile?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: dockerfile_fixture,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "docker-compose.yml?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: dockerfile_fixture,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "docker-compose.override.yml?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: dockerfile_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    let(:dockerfile_fixture) do
      fixture("github", "contents_dockerfile.json")
    end
    let(:dockerfile_2_fixture) do
      fixture("github", "contents_dockerfile.json")
    end

    it "fetches both Dockerfiles" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(Dockerfile Dockerfile-base Containerfile))
    end

    context "when an invalid encoding is present" do
      let(:dockerfile_2_fixture) { fixture("github", "contents_image.json") }

      it "fetches the first Dockerfile, and ignores the invalid one" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(%w(Dockerfile Containerfile))
      end
    end
  end

  context "with a custom named Dockerfile" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_docker_repo_custom.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "Dockerfile-base?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_dockerfile.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "docker-compose.override.yml?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_dockerfile.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the Dockerfile" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(Dockerfile-base))
    end
  end

  context "with a directory that doesn't exist" do
    let(:directory) { "/nonexistent" }

    before do
      stub_request(:get, url + "nonexistent?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 404,
          body: fixture("github", "not_found.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependabotError)
    end
  end

  context "with a YAML file" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_kubernetes_repo.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "pod.yaml?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: kubernetes_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    let(:kubernetes_fixture) { fixture("github", "contents_kubernetes.json") }

    it "fetches the pod.yaml" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(pod.yaml))
    end

    context "when an invalid encoding is present" do
      let(:kubernetes_fixture) { fixture("github", "contents_image.json") }

      it "raises a helpful error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "when an non-kubernetes YAML is present" do
      let(:kubernetes_fixture) { fixture("github", "contents_other_yaml.json") }

      it "raises a helpful error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependabotError)
      end
    end
  end

  context "with multiple YAMLs" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_kubernetes_repo_multiple.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "pod.yaml?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: kubernetes_fixture,
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "deployment.yaml?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: kubernetes_2_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    let(:kubernetes_fixture) { fixture("github", "contents_kubernetes.json") }
    let(:kubernetes_2_fixture) { fixture("github", "contents_kubernetes.json") }

    it "fetches both YAMLs" do
      expect(file_fetcher_instance.files.count).to eq(2)
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(deployment.yaml pod.yaml))
    end

    context "when an invalid encoding is present" do
      let(:kubernetes_2_fixture) { fixture("github", "contents_image.json") }

      it "fetches the first yaml, and ignores the invalid one" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(%w(pod.yaml))
      end
    end

    context "with a Helm values file" do
      matching_filenames = [
        "other.values.yml",
        "other.values.yaml",
        "other-values.yml",
        "other-values.yaml",
        "other_values.yml",
        "other_values.yaml",
        "values.yml",
        "values.yaml",
        "values-other.yml",
        "values-other.yaml",
        "values_other.yml",
        "values_other.yaml",
        "values2.yml",
        "values2.yaml"
      ]

      before do
        stub_request(:get, url + "?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_helm_repo.json"),
            headers: { "content-type" => "application/json" }
          )

        matching_filenames.each do |fname|
          stub_request(:get, File.join(url, "#{fname}?ref=sha"))
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: values_fixture,
              headers: { "content-type" => "application/json" }
            )
        end
      end

      let(:values_fixture) { fixture("github", "contents_values_yaml.json") }

      it "fetches the values.yaml" do
        expect(file_fetcher_instance.files.count).to eq(matching_filenames.length)
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(matching_filenames)
      end
    end
  end
end
