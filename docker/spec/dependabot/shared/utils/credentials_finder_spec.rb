# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/shared/utils/credentials_finder"
require "aws-sdk-ecr"
require "base64"

RSpec.describe Dependabot::Shared::Utils::CredentialsFinder do
  subject(:finder) { described_class.new(credentials) }

  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "docker_registry",
      "registry" => "695729449481.dkr.ecr.eu-west-2.amazonaws.com",
      "username" => "grey",
      "password" => "pa55word"
    })]
  end

  describe "#credentials_for_registry" do
    subject(:found_credentials) { finder.credentials_for_registry(registry) }

    let(:registry) { "my.registry.com" }

    context "with no matching credentials" do
      let(:registry) { "my.registry.com" }

      it { is_expected.to be_nil }
    end

    context "with a non-AWS registry" do
      let(:registry) { "my.registry.com" }
      let(:credentials) do
        [Dependabot::Credential.new({
          "type" => "docker_registry",
          "registry" => "my.registry.com",
          "username" => "grey",
          "password" => "pa55word"
        })]
      end

      it { is_expected.to eq(credentials.first) }
    end

    context "with an AWS registry" do
      let(:registry) { "695729449481.dkr.ecr.eu-west-2.amazonaws.com" }

      context "with 'AWS' as the username" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "docker_registry",
            "registry" => "695729449481.dkr.ecr.eu-west-2.amazonaws.com",
            "username" => "AWS",
            "password" => "pa55word"
          })]
        end

        it { is_expected.to eq(credentials.first) }
      end

      context "without a username or password" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "docker_registry",
            "registry" => "695729449481.dkr.ecr.eu-west-2.amazonaws.com"
          })]
        end

        context "when there is a valid AWS response (via proxying)" do
          before do
            stub_request(:post, "https://api.ecr.eu-west-2.amazonaws.com/")
              .and_return(
                status: 200,
                body: fixture("docker", "ecr_responses", "auth_data")
              )
          end

          it "returns details without credentials" do
            expect(found_credentials.to_h).to eq(
              "type" => "docker_registry",
              "registry" => "695729449481.dkr.ecr.eu-west-2.amazonaws.com"
            )
          end
        end
      end

      context "with as AKID as the username" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "docker_registry",
            "registry" => "695729449481.dkr.ecr.eu-west-2.amazonaws.com",
            "username" => "AKIAIHYCC4QXL4X2OTCQ",
            "password" => "pa55word"
          })]
        end

        context "when using an invalid secret key as the password" do
          before do
            stub_request(:post, "https://api.ecr.eu-west-2.amazonaws.com/")
              .and_return(
                status: 403,
                body: fixture("docker", "ecr_responses", "invalid_token")
              )
          end

          it "raises a PrivateSourceAuthenticationFailure error" do
            error_class = Dependabot::PrivateSourceAuthenticationFailure
            expect { finder.credentials_for_registry(registry) }
              .to raise_error(error_class) do |error|
                expect(error.source)
                  .to eq("695729449481.dkr.ecr.eu-west-2.amazonaws.com")
              end
          end
        end

        context "when an invalid secret key is used as the password (another type)" do
          before do
            stub_request(:post, "https://api.ecr.eu-west-2.amazonaws.com/")
              .and_return(
                status: 403,
                body: fixture(
                  "docker",
                  "ecr_responses",
                  "invalid_signature_exception"
                )
              )
          end

          it "raises a PrivateSourceAuthenticationFailure error" do
            error_class = Dependabot::PrivateSourceAuthenticationFailure
            expect { finder.credentials_for_registry(registry) }
              .to raise_error(error_class) do |error|
                expect(error.source)
                  .to eq("695729449481.dkr.ecr.eu-west-2.amazonaws.com")
              end
          end
        end

        context "when a valid secret key is used as the password" do
          before do
            stub_request(:post, "https://api.ecr.eu-west-2.amazonaws.com/")
              .and_return(
                status: 200,
                body: fixture("docker", "ecr_responses", "auth_data")
              )
          end

          it "returns an updated set of credentials" do
            expect(found_credentials.to_h).to eq(
              "type" => "docker_registry",
              "registry" => "695729449481.dkr.ecr.eu-west-2.amazonaws.com",
              "username" => "AWS",
              "password" => "secret_aws_password"
            )
          end
        end
      end

      context "when using the default credentials provider" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "docker_registry",
            "registry" => "695729449481.dkr.ecr.eu-west-2.amazonaws.com"
          })]
        end

        context "when there is a valid AWS response" do
          let(:ecr_stub) { Aws::ECR::Client.new(stub_responses: true) }

          before do
            ecr_stub.stub_responses(
              :get_authorization_token,
              authorization_data:
                [authorization_token: Base64.encode64("foo:bar")]
            )
          end

          it "returns updated, valid credentials" do
            allow(Aws::ECR::Client).to receive(:new).with(region: "eu-west-2").and_return(ecr_stub)

            expect(found_credentials.to_h).to eq(
              "type" => "docker_registry",
              "registry" => "695729449481.dkr.ecr.eu-west-2.amazonaws.com",
              "username" => "foo",
              "password" => "bar"
            )
          end
        end
      end
    end
  end

  describe "#base_registry" do
    subject(:base_registry) { finder.base_registry }

    context "with private registry and replaces-base true" do
      let(:credentials) do
        [Dependabot::Credential.new({
          "type" => "docker_registry",
          "registry" => "registry-host.io:5000",
          "username" => "grey",
          "password" => "pa55word",
          "replaces-base" => true
        })]
      end

      it { is_expected.to eq("registry-host.io:5000") }
    end

    context "with private registry and replaces-base false" do
      let(:credentials) do
        [Dependabot::Credential.new({
          "type" => "docker_registry",
          "registry" => "registry-host.io:5000",
          "username" => "grey",
          "password" => "pa55word",
          "replaces-base" => false
        })]
      end

      it { is_expected.to eq("registry.hub.docker.com") }
    end

    context "with multiple private registries and mixed value of replaces-base" do
      let(:credentials) do
        [Dependabot::Credential.new({
          "type" => "docker_registry",
          "registry" => "registry-host.io:5000",
          "username" => "grey",
          "password" => "pa55word",
          "replaces-base" => false
        }), Dependabot::Credential.new({
          "type" => "docker_registry",
          "registry" => "registry-host-new.io:5000",
          "username" => "ankit",
          "password" => "pa55word",
          "replaces-base" => true
        })]
      end

      it { is_expected.to eq("registry-host-new.io:5000") }
    end
  end
end
