# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/swift/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Swift::MetadataFinder do
  it_behaves_like "a dependency metadata finder"

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  describe "#source_url" do
    context "with a direct dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "reactiveswift",
          version: "7.1.1",
          requirements: [{
            file: "package.swfit",
            requirement: "= 7.1.1",
            groups: [],
            source: {
              "type" => "git",
              "url" => "https://github.com/reactivecocoa/reactiveswift",
              "ref" => "7.1.1",
              "branch" => nil
            }
          }],
          package_manager: "swift"
        )
      end

      it "works" do
        expect(finder.source_url).to eq "https://github.com/reactivecocoa/reactiveswift"
      end
    end

    context "with an indirect dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "reactiveswift",
          version: "7.1.1",
          requirements: [],
          subdependency_metadata: [
            {
              source: {
                "type" => "git",
                "url" => "https://github.com/reactivecocoa/reactiveswift",
                "ref" => "7.1.1",
                "branch" => nil
              }
            }
          ],
          package_manager: "swift"
        )
      end

      it "works" do
        expect(finder.source_url).to eq "https://github.com/reactivecocoa/reactiveswift"
      end
    end
  end
end
