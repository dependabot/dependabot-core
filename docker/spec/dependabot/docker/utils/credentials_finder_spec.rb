# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker/utils/credentials_finder"

RSpec.describe Dependabot::Docker::Utils::CredentialsFinder do
  subject(:finder) { described_class.new(credentials) }
  let(:credentials) do
    [{
      "type" => "docker_registry",
      "registry" => "695729449481.dkr.ecr.eu-west-2.amazonaws.com",
      "username" => "grey",
      "password" => "pa55word"
    }]
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
        [{
          "type" => "docker_registry",
          "registry" => "my.registry.com",
          "username" => "grey",
          "password" => "pa55word"
        }]
      end

      it { is_expected.to eq(credentials.first) }
    end

    context "with an AWS registry" do
      let(:registry) { "695729449481.dkr.ecr.eu-west-2.amazonaws.com" }

      context "with 'AWS' as the username" do
        let(:credentials) do
          [{
            "type" => "docker_registry",
            "registry" => "695729449481.dkr.ecr.eu-west-2.amazonaws.com",
            "username" => "AWS",
            "password" => "pa55word"
          }]
        end

        it { is_expected.to eq(credentials.first) }
      end

      context "with as AKID as the username" do
        let(:credentials) do
          [{
            "type" => "docker_registry",
            "registry" => "695729449481.dkr.ecr.eu-west-2.amazonaws.com",
            "username" => "AKIAIHYCC4QXL4X2OTCQ",
            "password" => "pa55word"
          }]
        end

        context "and an invalid secret key as the password" do
          before do
            stub_request(:post, "https://api.ecr.eu-west-2.amazonaws.com/").
              and_return(
                status: 403,
                body: fixture("docker", "ecr_responses", "invalid_token")
              )
          end

          it "raises a PrivateSourceAuthenticationFailure error" do
            error_class = Dependabot::PrivateSourceAuthenticationFailure
            expect { finder.credentials_for_registry(registry) }.
              to raise_error(error_class) do |error|
                expect(error.source).
                  to eq("695729449481.dkr.ecr.eu-west-2.amazonaws.com")
              end
          end
        end

        context "and an invalid secret key as the password (another type)" do
          before do
            stub_request(:post, "https://api.ecr.eu-west-2.amazonaws.com/").
              and_return(
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
            expect { finder.credentials_for_registry(registry) }.
              to raise_error(error_class) do |error|
                expect(error.source).
                  to eq("695729449481.dkr.ecr.eu-west-2.amazonaws.com")
              end
          end
        end

        context "and a valid secret key as the password" do
          before do
            stub_request(:post, "https://api.ecr.eu-west-2.amazonaws.com/").
              and_return(
                status: 200,
                body: fixture("docker", "ecr_responses", "auth_data")
              )
          end

          it "returns an updated set of credentials" do
            expect(found_credentials).to eq(
              "type" => "docker_registry",
              "registry" => "695729449481.dkr.ecr.eu-west-2.amazonaws.com",
              "username" => "AWS",
              "password" => "secret_aws_password"
            )
          end
        end
      end
    end
  end
end
