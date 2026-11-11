# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/clojure/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Clojure::MetadataFinder do
  subject(:finder) { described_class.new(dependency: dependency, credentials: []) }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "ring:ring-core",
      version: "1.12.2",
      requirements: [{
        file: "project.clj",
        requirement: "1.12.2",
        groups: ["dependencies"],
        source: { type: "maven_repo", url: "https://repo.clojars.org" }
      }],
      package_manager: "clojure"
    )
  end

  before do
    stub_request(:get, "https://repo.clojars.org/ring/ring-core/1.12.2/ring-core-1.12.2.pom")
      .to_return(status: 200, body: fixture("poms", "ring_core.pom"))
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    it "reads the SCM URL from the POM" do
      expect(finder.source_url).to eq("https://github.com/ring-clojure/ring")
    end
  end
end
