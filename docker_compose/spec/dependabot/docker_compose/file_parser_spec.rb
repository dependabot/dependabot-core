# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/docker_compose/file_parser"

require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::DockerCompose::FileParser do
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:composefile_fixture_name) { "tag" }
  let(:composefile_body) do
    fixture("docker_compose", "composefiles", composefile_fixture_name)
  end
  let(:composefile) do
    Dependabot::DependencyFile.new(
      name: "docker-compose.yml",
      content: composefile_body
    )
  end
  let(:files) { [composefile] }

  before do
    allow(Dependabot::Experiments).to receive(:enabled?).with(:enable_beta_ecosystems).and_return(true)
  end

  it_behaves_like "a dependency file parser"

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(1) }

    describe "the first dependency" do
      subject(:dependency) { dependencies.first }

      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: "docker-compose.yml",
          source: { tag: "17.04" }
        }]
      end

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("ubuntu")
        expect(dependency.version).to eq("17.04")
        expect(dependency.requirements).to eq(expected_requirements)
      end
    end

    context "with no tag or digest" do
      let(:composefile_fixture_name) { "bare" }

      its(:length) { is_expected.to eq(0) }
    end

    context "with a namespace" do
      let(:composefile_fixture_name) { "namespace" }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: { tag: "17.04" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("my-fork/ubuntu")
          expect(dependency.version).to eq("17.04")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with a non-numeric version" do
      let(:composefile_fixture_name) { "non_numeric_version" }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: { tag: "artful" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("ubuntu")
          expect(dependency.version).to eq("artful")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with a digest" do
      let(:composefile_fixture_name) { "digest" }
      let(:registry_tags) { fixture("docker", "registry_tags", "ubuntu.json") }
      let(:digest_headers) do
        JSON.parse(
          fixture("docker", "registry_manifest_headers", "ubuntu_12.04.5.json")
        )
      end

      let(:repo_url) { "https://registry.hub.docker.com/v2/library/ubuntu/" }

      before do
        auth_url = "https://auth.docker.io/token?service=registry.docker.io"
        stub_request(:get, auth_url)
          .and_return(status: 200, body: { token: "token" }.to_json)

        tags_url = repo_url + "tags/list"
        stub_request(:get, tags_url)
          .and_return(status: 200, body: registry_tags)
      end

      context "when there is a matching tag" do
        before do
          stub_request(:head, repo_url + "manifests/10.04")
            .and_return(status: 404)

          stub_request(:head, repo_url + "manifests/12.04.5")
            .and_return(status: 200, body: "", headers: digest_headers)
        end

        its(:length) { is_expected.to eq(1) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          let(:expected_requirements) do
            [{
              requirement: nil,
              groups: [],
              file: "docker-compose.yml",
              source: {
                digest: "18305429afa14ea462f810146ba44d4363ae76e4c8d" \
                        "fc38288cf73aa07485005"
              }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("ubuntu")
            expect(dependency.version).to eq("18305429afa14ea462f810146ba44d4363ae76e4c8dfc38288cf73aa07485005")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end

        context "with a private registry" do
          let(:composefile_fixture_name) { "private_digest" }
          let(:repo_url) { "https://registry-host.io:5000/v2/myreg/ubuntu/" }

          context "with good authentication credentials" do
            let(:parser) do
              described_class.new(
                dependency_files: files,
                credentials: credentials,
                source: source
              )
            end
            let(:credentials) do
              [{
                "type" => "docker_registry",
                "registry" => "registry-host.io:5000",
                "username" => "grey",
                "password" => "pa55word"
              }]
            end

            its(:length) { is_expected.to eq(1) }

            describe "the first dependency" do
              subject(:dependency) { dependencies.first }

              let(:expected_requirements) do
                [{
                  requirement: nil,
                  groups: [],
                  file: "docker-compose.yml",
                  source: {
                    registry: "registry-host.io:5000",
                    digest: "18305429afa14ea462f810146ba44d4363ae76" \
                            "e4c8dfc38288cf73aa07485005"
                  }
                }]
              end

              it "has the right details" do
                expect(dependency).to be_a(Dependabot::Dependency)
                expect(dependency.name).to eq("myreg/ubuntu")
                expect(dependency.version).to eq("18305429afa14ea462f810146ba44d4363ae76e4c8dfc38288cf73aa07485005")
                expect(dependency.requirements).to eq(expected_requirements)
              end
            end

            context "when there is no username and password" do
              let(:credentials) do
                [{
                  "type" => "docker_registry",
                  "registry" => "registry-host.io:5000"
                }]
              end

              its(:length) { is_expected.to eq(1) }
            end
          end
        end
      end
    end

    context "with multiple services" do
      let(:composefile_fixture_name) { "multiple" }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: { tag: "17.04" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("ubuntu")
          expect(dependency.version).to eq("17.04")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the second dependency" do
        subject(:dependency) { dependencies.last }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: { tag: "3.6.3" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("python")
          expect(dependency.version).to eq("3.6.3")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      context "when the dependencies are identical" do
        let(:composefile_fixture_name) { "multiple_identical" }

        its(:length) { is_expected.to eq(1) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          let(:expected_requirements) do
            [{
              requirement: nil,
              groups: [],
              file: "docker-compose.yml",
              source: { tag: "10-alpine" }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("node")
            expect(dependency.version).to eq("10-alpine")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end
      end
    end

    context "with a v1 dockerhub reference and a tag" do
      let(:composefile_fixture_name) { "v1_tag" }

      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: { tag: "17.04" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("myreg/ubuntu")
          expect(dependency.version).to eq("17.04")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with a private registry and a tag" do
      let(:composefile_fixture_name) { "private_tag" }

      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: {
              registry: "registry-host.io:5000",
              tag: "17.04"
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("myreg/ubuntu")
          expect(dependency.version).to eq("17.04")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      context "when the registry has no port" do
        let(:composefile_fixture_name) { "private_no_port" }

        its(:length) { is_expected.to eq(1) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          let(:expected_requirements) do
            [{
              requirement: nil,
              groups: [],
              file: "docker-compose.yml",
              source: {
                registry: "aws-account-id.dkr.ecr.region.amazonaws.com",
                tag: "17.04"
              }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("myreg/ubuntu")
            expect(dependency.version).to eq("17.04")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end
      end
    end

    context "with a non-standard filename" do
      let(:composefile) do
        Dependabot::DependencyFile.new(
          name: "custom-name",
          content: composefile_body
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "custom-name",
            source: { tag: "17.04" }
          }]
        end

        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with multiple composefiles" do
      let(:files) { [composefile, dockefile2] }
      let(:dockefile2) do
        Dependabot::DependencyFile.new(
          name: "custom-name",
          content: composefile_body2
        )
      end
      let(:composefile_body2) do
        fixture("docker_compose", "composefiles", "namespace")
      end

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: { tag: "17.04" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("ubuntu")
          expect(dependency.version).to eq("17.04")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the second dependency" do
        subject(:dependency) { dependencies.last }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "custom-name",
            source: { tag: "17.04" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("my-fork/ubuntu")
          expect(dependency.version).to eq("17.04")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with a non-numeric version" do
      let(:composefile_fixture_name) { "inline_dockerfile" }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: { tag: "10.11.2-jammy" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("mariadb")
          expect(dependency.version).to eq("10.11.2-jammy")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end
  end
end
