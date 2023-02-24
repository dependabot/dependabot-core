# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/path_converter"

RSpec.describe Dependabot::GoModules::PathConverter do
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

    xcontext "with a vanity URL that redirects" do
      let(:path) { "code.cloudfoundry.org/bytefmt" }
      it { is_expected.to eq("https://github.com/cloudfoundry/bytefmt") }
    end

    context "with a vanity URL that 404s, but is otherwise valid" do
      let(:path) { "gonum.org/v1/gonum" }
      it { is_expected.to eq("https://github.com/gonum/gonum") }
    end

    context "with a path that already includes a scheme" do
      let(:path) { "https://github.com/drewolson/testflight" }
      it { is_expected.to eq("https://github.com/drewolson/testflight") }
    end
  end
end
