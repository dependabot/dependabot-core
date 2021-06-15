# frozen_string_literal: true

require "spec_helper"
require "dependabot/bundler/update_checker"

RSpec.describe Dependabot::Bundler::UpdateChecker::LatestVersionFinder::DependencySource do
  let(:project_name) { "git_source" }
  let(:files) { project_dependency_files(File.join("bundler2", project_name)) }
  let(:source) { described_class.new(dependency: nil, dependency_files: files, credentials: [], options: {}) }

  describe "#inaccessible_git_dependencies", :vcr do
    subject(:inaccessible_git_dependencies) { source.inaccessible_git_dependencies }

    it "is empty when all dependencies are accessible" do
      expect(inaccessible_git_dependencies).to be_empty
    end

    context "with inaccessible dependency", :vcr do
      let(:project_name) { "private_git_source" }

      it "includes inaccessible dependency" do
        expect(inaccessible_git_dependencies.size).to eq(1)
        expect(inaccessible_git_dependencies.first).to eq({
          "auth_uri" => "https://github.com/no-exist-sorry/prius.git/info/refs?service=git-upload-pack",
          "uri" => "git@github.com:no-exist-sorry/prius"
        })
      end
    end

    context "with non-URI dependency", :vcr do
      let(:project_name) { "git_source_invalid_github" }

      it "includes invalid dependency" do
        expect(inaccessible_git_dependencies.size).to eq(1)
        expect(inaccessible_git_dependencies.first).to eq({
          "auth_uri" => "dependabot-fixtures/business.git/info/refs?service=git-upload-pack",
          "uri" => "dependabot-fixtures/business"
        })
      end
    end
  end
end
