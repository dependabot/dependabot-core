# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/go_modules/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::GoModules::MetadataFinder do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "2.1.0",
      requirements: requirements,
      package_manager: "go_modules"
    )
  end
  let(:requirements) do
    [{
      file: "go.mod",
      requirement: "v2.1.0",
      groups: [],
      source: source
    }]
  end
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_name) { "github.com/satori/go.uuid" }
  let(:source) { nil }

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "with no requirements (i.e., a subdependency)" do
      let(:requirements) { [] }

      it { is_expected.to eq("https://github.com/satori/go.uuid") }

      context "for a golang.org project" do
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
  end

  describe "#look_up_source_using_go_list" do
    subject { described_class.look_up_source_using_go_list(path) }

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
