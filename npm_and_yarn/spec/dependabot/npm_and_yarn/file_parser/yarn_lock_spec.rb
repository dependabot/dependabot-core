# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser"

RSpec.describe Dependabot::NpmAndYarn::FileParser::YarnLock do
  let(:yarn_lock) { described_class.new(dependency_file, dealias_packages: dealias_packages) }
  let(:dealias_packages) { false }
  let(:dependency_file) do
    project_dependency_files("yarn/aliased_dependency").find { |f| f.name == "yarn.lock" }
  end

  describe "#dependencies" do
    subject(:dependencies) { yarn_lock.dependencies }

    context "when dealias_packages is disabled (default)" do
      it "excludes aliased packages" do
        expect(dependencies.dependencies.map(&:name)).not_to include("fetch-factory")
        expect(dependencies.dependencies.map(&:name)).not_to include("my-fetch-factory")
      end

      it "includes non-aliased packages" do
        expect(dependencies.dependencies.map(&:name)).to include("etag")
        expect(dependencies.dependencies.map(&:name)).to include("node-fetch")
      end
    end

    context "when dealias_packages is enabled" do
      let(:dealias_packages) { true }

      it "includes the real package name from the alias" do
        expect(dependencies.dependencies.map(&:name)).to include("fetch-factory")
      end

      it "does not include the alias name" do
        expect(dependencies.dependencies.map(&:name)).not_to include("my-fetch-factory")
      end

      it "resolves the correct version for the aliased package" do
        aliased_dep = dependencies.dependencies.find { |d| d.name == "fetch-factory" }
        expect(aliased_dep.version).to eq("0.0.1")
      end

      it "still includes non-aliased packages" do
        expect(dependencies.dependencies.map(&:name)).to include("etag")
        expect(dependencies.dependencies.map(&:name)).to include("node-fetch")
      end
    end
  end
end
