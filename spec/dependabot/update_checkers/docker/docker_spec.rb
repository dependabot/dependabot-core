# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/update_checkers/docker/docker"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Docker::Docker do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      github_access_token: "token"
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: [
        {
          requirement: nil,
          groups: [],
          file: "Dockerfile",
          source: { type: "tag" }
        }
      ],
      package_manager: "docker"
    )
  end
  let(:dependency_name) { "ubuntu" }
  let(:version) { "17.04" }
  let(:registry_tags) { fixture("docker", "registry_tags", "ubuntu.json") }

  before do
    ping_url = "https://registry.hub.docker.com/v2/"
    stub_request(:get, ping_url).and_return(status: 200)

    auth_url = "https://auth.docker.io/token?service=registry.docker.io"
    stub_request(:get, auth_url).
      and_return(status: 200, body: { token: "token" }.to_json)

    tags_url = "https://registry.hub.docker.com/v2/library/ubuntu/tags/list"
    stub_request(:get, tags_url).
      and_return(status: 200, body: registry_tags)
  end

  describe "#needs_update?" do
    subject { checker.needs_update? }

    context "given an outdated dependency" do
      let(:version) { "17.04" }
      it { is_expected.to be_truthy }
    end

    context "given an up-to-date dependency" do
      let(:version) { "17.10" }
      it { is_expected.to be_falsey }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    it { is_expected.to eq(Gem::Version.new("17.10")) }

    context "when the dependency has a non-numeric version" do
      let(:version) { "artful" }
      it { is_expected.to be_nil }
    end

    context "when the dependency has a namespace" do
      let(:dependency_name) { "moj/ruby" }
      let(:registry_tags) { fixture("docker", "registry_tags", "ruby.json") }
      before do
        ping_url = "https://registry.hub.docker.com/v2/"
        stub_request(:get, ping_url).and_return(status: 200)

        auth_url = "https://auth.docker.io/token?service=registry.docker.io"
        stub_request(:get, auth_url).
          and_return(status: 200, body: { token: "token" }.to_json)

        tags_url = "https://registry.hub.docker.com/v2/moj/ruby/tags/list"
        stub_request(:get, tags_url).
          and_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq(Gem::Version.new("2.4.2")) }
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    before { allow(checker).to receive(:latest_version).and_return("delegate") }
    it { is_expected.to eq("delegate") }
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements }
    it { is_expected.to eq(dependency.requirements) }
  end
end
