# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/docker/docker"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Docker::Docker do
  it_behaves_like "a dependency file parser"

  let(:files) { [dockerfile] }
  let(:dockerfile) do
    Dependabot::DependencyFile.new(
      name: "Dockerfile",
      content: dockerfile_body
    )
  end
  let(:dockerfile_body) { fixture("docker", "dockerfiles", "tag") }
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(1) }

    describe "the first dependency" do
      subject(:dependency) { dependencies.first }
      let(:expected_requirements) do
        [
          {
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: { type: "tag" }
          }
        ]
      end

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("ubuntu")
        expect(dependency.version).to eq("17.04")
        expect(dependency.requirements).to eq(expected_requirements)
      end
    end

    context "with no tag or digest" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "bare") }
      its(:length) { is_expected.to eq(0) }
    end

    context "with a name" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "name") }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }
        let(:expected_requirements) do
          [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { type: "tag" }
            }
          ]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("ubuntu")
          expect(dependency.version).to eq("17.04")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with a namespace" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "namespace") }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }
        let(:expected_requirements) do
          [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { type: "tag" }
            }
          ]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("my_fork/ubuntu")
          expect(dependency.version).to eq("17.04")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with a FROM line written by a nutcase" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "case") }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }
        let(:expected_requirements) do
          [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { type: "tag" }
            }
          ]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("ubuntu")
          expect(dependency.version).to eq("17.04")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with a digest" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "digest") }
      let(:registry_tags) { fixture("docker", "registry_tags", "ubuntu.json") }
      let(:digest_headers) do
        JSON.parse(
          fixture("docker", "registry_manifest_headers", "ubuntu_12.04.5.json")
        )
      end

      before do
        registry_url = "https://registry.hub.docker.com/v2/"
        stub_request(:get, registry_url).and_return(status: 200)

        auth_url = "https://auth.docker.io/token?service=registry.docker.io"
        stub_request(:get, auth_url).
          and_return(status: 200, body: { token: "token" }.to_json)

        tags_url = registry_url + "library/ubuntu/tags/list"
        stub_request(:get, tags_url).
          and_return(status: 200, body: registry_tags)
      end

      context "that doesn't match any tags" do
        let(:registry_tags) do
          fixture("docker", "registry_tags", "small_ubuntu.json")
        end
        before { digest_headers["docker_content_digest"] = "nomatch" }

        before do
          ubuntu_url = "https://registry.hub.docker.com/v2/library/ubuntu/"
          stub_request(:head, /#{Regexp.quote(ubuntu_url)}manifests/).
            and_return(status: 200, body: "", headers: digest_headers)
        end

        its(:length) { is_expected.to eq(0) }
      end

      context "that matches a tag" do
        before do
          ubuntu_url = "https://registry.hub.docker.com/v2/library/ubuntu/"
          stub_request(:head, ubuntu_url + "manifests/10.04").
            and_return(status: 404)

          stub_request(:head, ubuntu_url + "manifests/12.04.5").
            and_return(status: 200, body: "", headers: digest_headers)
        end

        its(:length) { is_expected.to eq(1) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }
          let(:expected_requirements) do
            [
              {
                requirement: nil,
                groups: [],
                file: "Dockerfile",
                source: { type: "digest" }
              }
            ]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("ubuntu")
            expect(dependency.version).to eq("12.04.5")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end
      end
    end

    context "with a private registry and a tag" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "private_tag") }

      # TODO: support private registries
      it "raises a helpful error message" do
        expect { parser.parse }.
          to raise_error(Dependabot::PrivateSourceNotReachable)
      end
    end
  end
end
