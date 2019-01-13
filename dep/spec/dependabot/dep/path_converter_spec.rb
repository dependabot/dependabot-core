# frozen_string_literal: true

require "spec_helper"
require "dependabot/dep/path_converter"

RSpec.describe Dependabot::Dep::PathConverter do
  describe ".git_url_for_path" do
    subject { described_class.git_url_for_path(path) }

    let(:path) { "gopkg.in/guregu/null.v3" }

    context "with a path that is immediately recognisable as a git source" do
      let(:path) { "github.com/drewolson/testflight" }
      it { is_expected.to eq("https://github.com/drewolson/testflight") }
    end

    context "with a golang.org path" do
      let(:path) { "golang.org/x/tools" }
      it { is_expected.to eq("https://github.com/golang/tools") }
    end

    context "with a path that ends in .git" do
      let(:path) { "git.fd.io/govpp.git" }
      it { is_expected.to eq("https://git.fd.io/govpp.git") }
    end

    context "with a vanity URL that needs to be fetched" do
      let(:path) { "k8s.io/apimachinery" }
      it { is_expected.to eq("https://github.com/kubernetes/apimachinery") }
    end

    context "with a vanity URL that redirects" do
      let(:path) { "code.cloudfoundry.org/bytefmt" }
      it { is_expected.to eq("https://github.com/cloudfoundry/bytefmt") }
    end

    context "with a path that already includes a scheme" do
      let(:path) { "https://github.com/drewolson/testflight" }
      it { is_expected.to eq("https://github.com/drewolson/testflight") }
    end
  end

  describe ".git_url_for_path_without_go_helper" do
    subject { described_class.git_url_for_path_without_go_helper(path) }

    let(:path) { "gopkg.in/guregu/null.v3" }

    context "with a path that is immediately recognisable as a git source" do
      let(:path) { "github.com/drewolson/testflight" }
      it { is_expected.to eq("https://github.com/drewolson/testflight") }
    end

    context "with a golang.org path" do
      let(:path) { "golang.org/x/tools" }
      it { is_expected.to eq("https://github.com/golang/tools") }
    end

    context "with a path that ends in .git" do
      let(:path) { "git.fd.io/govpp.git" }
      it { is_expected.to eq("https://git.fd.io/govpp.git") }
    end

    context "with a vanity URL that needs to be fetched" do
      let(:path) { "k8s.io/apimachinery" }

      before do
        stub_request(:get, "https://k8s.io/apimachinery?go-get=1").
          to_return(status: 200, body: vanity_response)
      end
      let(:vanity_response) do
        fixture("repo_responses", "k8s_io_apimachinery.html")
      end

      it { is_expected.to eq("https://github.com/kubernetes/apimachinery") }

      context "and returns a git source hosted with an unknown provider" do
        let(:vanity_response) do
          fixture("repo_responses", "unknown_git_source.html")

          it { is_expected.to eq("https://sf.com/kubernetes/apimachinery") }
        end
      end
    end
  end
end
