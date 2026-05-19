# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser"

RSpec.describe Dependabot::NpmAndYarn::FileParser::JsonLock do
  let(:json_lock) { described_class.new(dependency_file, dealias_packages: dealias_packages) }
  let(:dealias_packages) { false }
  let(:dependency_file) do
    project_dependency_files("grapher/npm_with_alias").find { |f| f.name == "package-lock.json" }
  end

  describe "#dependencies" do
    subject(:dependencies) { json_lock.dependencies.dependencies }

    context "when dealias_packages is disabled (default)" do
      it "uses the alias name from the package path" do
        expect(dependencies.map(&:name)).to include("my-is-number")
        expect(dependencies.map(&:name)).not_to include("is-number")
      end
    end

    context "when dealias_packages is enabled" do
      let(:dealias_packages) { true }

      it "uses the real package name from the lockfile entry" do
        expect(dependencies.map(&:name)).to include("is-number")
        expect(dependencies.map(&:name)).not_to include("my-is-number")
      end
    end
  end
end
