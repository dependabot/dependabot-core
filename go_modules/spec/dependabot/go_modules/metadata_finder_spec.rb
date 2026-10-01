# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/go_modules/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::GoModules::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:source) { nil }
  let(:dependency_name) { "github.com/satori/go.uuid" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:requirements) do
    [{
      file: "go.mod",
      requirement: "v2.1.0",
      groups: [],
      source: source
    }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "2.1.0",
      requirements: requirements,
      package_manager: "go_modules"
    )
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    let(:api_url) { "https://pkg.go.dev/v1/module/#{dependency_name}" }
    let(:repo_url) { "https://github.com/satori/go.uuid" }
    let(:response_status) { repo_url ? 200 : 404 }
    let(:response_body) do
      repo_url ? { repoUrl: repo_url }.to_json : '{"code":404,"message":"not found","fixes":null}'
    end

    before do
      stub_request(:get, api_url).to_return(status: response_status, body: response_body)
    end

    context "with no requirements (i.e., a subdependency)" do
      let(:requirements) { [] }

      it { is_expected.to eq("https://github.com/satori/go.uuid") }

      context "when dealing with a golang.org project" do
        let(:dependency_name) { "golang.org/x/text" }

        it { is_expected.to eq("https://github.com/golang/text") }
      end
    end

    context "with default requirements" do
      let(:source) do
        {
          type: "default",
          source: "github.com/alias/go.uuid"
        }
      end

      it { is_expected.to eq("https://github.com/satori/go.uuid") }
    end

    context "with a module path that ends in .git" do
      let(:dependency_name) { "git.fd.io/govpp.git" }
      let(:repo_url) { "https://github.com/FDio/govpp" }

      it { is_expected.to eq(repo_url) }
    end

    context "with a vanity import path" do
      let(:dependency_name) { "k8s.io/apimachinery" }
      let(:repo_url) { "https://github.com/kubernetes/apimachinery" }

      it { is_expected.to eq(repo_url) }
    end

    context "with a vanity import path whose host redirects" do
      let(:dependency_name) { "code.cloudfoundry.org/bytefmt" }
      let(:repo_url) { "https://github.com/cloudfoundry/bytefmt" }

      it { is_expected.to eq(repo_url) }
    end

    context "with a vanity import path whose host 404s" do
      let(:dependency_name) { "gonum.org/v1/gonum" }
      let(:repo_url) { "https://github.com/gonum/gonum" }

      it { is_expected.to eq(repo_url) }
    end

    context "with a module pkg.go.dev doesn't know about" do
      let(:dependency_name) { "gopkg.in/guregu/null.v3" }
      let(:repo_url) { nil }

      it { is_expected.to be_nil }
    end

    context "with a nested golang.org/x module" do
      let(:dependency_name) { "golang.org/x/tools/gopls" }

      it "resolves to the mirror's repo root rather than the nonexistent nested mirror path" do
        expect(source_url).to eq("https://github.com/golang/tools")
        expect(a_request(:get, api_url)).not_to have_been_made
      end
    end

    context "with a bare golang.org/x path" do
      let(:dependency_name) { "golang.org/x" }
      let(:repo_url) { nil }

      it "falls through to pkg.go.dev instead of matching the mirror shortcut" do
        expect(source_url).to be_nil
        expect(a_request(:get, api_url)).to have_been_made.once
      end
    end

    context "when pkg.go.dev returns an unexpected error status" do
      let(:response_status) { 500 }
      let(:response_body) { "Internal Server Error" }

      it { is_expected.to be_nil }
    end

    context "when pkg.go.dev is unreachable" do
      before { allow(Dependabot::RegistryClient).to receive(:get).and_raise(Excon::Error::Timeout) }

      it { is_expected.to be_nil }
    end

    context "when pkg.go.dev returns a response that can't be parsed" do
      let(:response_status) { 200 }

      context "with a non-JSON body" do
        let(:response_body) { "not json" }

        it { is_expected.to be_nil }
      end

      context "with a repoUrl of the wrong type" do
        let(:response_body) { { repoUrl: %w(not a string) }.to_json }

        it { is_expected.to be_nil }
      end
    end
  end
end
