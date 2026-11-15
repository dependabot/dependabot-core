# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/nimble/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Nimble::MetadataFinder do
  subject(:finder) { described_class.new(dependency: dependency, credentials: []) }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "chronos",
      version: "4.2.0",
      package_manager: "nimble",
      requirements: [{ requirement: ">= 4.2.0", file: "example.nimble", groups: ["dependencies"], source: nil }]
    )
  end
  let(:package_index) { instance_double(Dependabot::Nimble::PackageIndex, repository_url: url) }
  let(:url) { "https://github.com/status-im/nim-chronos" }

  before { allow(Dependabot::Nimble::PackageIndex).to receive(:new).and_return(package_index) }

  it_behaves_like "a dependency metadata finder" do
    let(:source) { { "type" => "git", "url" => url } }
  end

  describe "#source_url" do
    it "is the repository the package index lists" do
      expect(finder.source_url).to eq("https://github.com/status-im/nim-chronos")
    end

    context "when the index does not know the package" do
      let(:url) { nil }

      it "has none" do
        expect(finder.source_url).to be_nil
      end
    end
  end
end
