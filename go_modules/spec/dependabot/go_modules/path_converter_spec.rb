# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/path_converter"

RSpec.describe Dependabot::GoModules::PathConverter do
  describe ".git_url_for_path" do
    subject(:resolved_url) { described_class.git_url_for_path(path) }

    let(:path) { "gopkg.in/guregu/null.v3" }
    let(:repo_url) { nil }
    let(:response_status) { repo_url ? 200 : 404 }
    let(:response_body) do
      repo_url ? { repoUrl: repo_url }.to_json : '{"code":404,"message":"not found","fixes":null}'
    end

    before do
      stub_request(:get, "https://pkg.go.dev/v1/module/#{path}")
        .to_return(status: response_status, body: response_body)
    end

    context "with a path that is immediately recognisable as a git source" do
      let(:path) { "github.com/drewolson/testflight" }
      let(:repo_url) { "https://github.com/drewolson/testflight" }

      it { is_expected.to eq(repo_url) }
    end

    context "with a golang.org path" do
      let(:path) { "golang.org/x/tools" }

      it { is_expected.to eq("https://github.com/golang/tools") }
    end

    context "with a path that ends in .git" do
      let(:path) { "git.fd.io/govpp.git" }
      let(:repo_url) { "https://git.fd.io/govpp.git" }

      it { is_expected.to eq(repo_url) }
    end

    context "with a vanity URL that needs to be fetched" do
      let(:path) { "k8s.io/apimachinery" }
      let(:repo_url) { "https://github.com/kubernetes/apimachinery" }

      it { is_expected.to eq(repo_url) }
    end

    context "with a vanity URL that redirects" do
      let(:path) { "code.cloudfoundry.org/bytefmt" }
      let(:repo_url) { "https://github.com/cloudfoundry/bytefmt" }

      it { is_expected.to eq(repo_url) }
    end

    context "with a vanity URL that 404s, but is otherwise valid" do
      let(:path) { "gonum.org/v1/gonum" }
      let(:repo_url) { "https://github.com/gonum/gonum" }

      it { is_expected.to eq(repo_url) }
    end

    context "with a path that already includes a scheme" do
      let(:path) { "https://github.com/drewolson/testflight" }

      it { is_expected.to be_nil }
    end

    context "with a nested golang.org/x module" do
      let(:path) { "golang.org/x/tools/gopls" }

      it "resolves to the mirror's repo root rather than the nonexistent nested mirror path" do
        expect(resolved_url).to eq("https://github.com/golang/tools")
        expect(a_request(:get, "https://pkg.go.dev/v1/module/#{path}")).not_to have_been_made
      end
    end

    context "with a bare golang.org/x path" do
      let(:path) { "golang.org/x" }

      it "falls through to pkg.go.dev instead of matching the mirror shortcut" do
        expect(resolved_url).to be_nil
        expect(a_request(:get, "https://pkg.go.dev/v1/module/#{path}")).to have_been_made.once
      end
    end

    context "when pkg.go.dev returns an unexpected error status" do
      let(:path) { "k8s.io/apimachinery" }
      let(:response_status) { 500 }
      let(:response_body) { "Internal Server Error" }

      it { is_expected.to be_nil }
    end

    context "when pkg.go.dev is unreachable" do
      let(:path) { "k8s.io/apimachinery" }

      before { stub_request(:get, "https://pkg.go.dev/v1/module/#{path}").to_timeout }

      it { is_expected.to be_nil }
    end

    context "when pkg.go.dev returns a response that can't be parsed" do
      let(:path) { "k8s.io/apimachinery" }
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
