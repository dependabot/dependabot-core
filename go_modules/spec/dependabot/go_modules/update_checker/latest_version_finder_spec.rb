# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/go_modules/native_helpers"
require "dependabot/go_modules/update_checker/latest_version_finder"

RSpec.describe Dependabot::GoModules::UpdateChecker::LatestVersionFinder do
  let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-lib" }

  let(:dependency_version) { "1.0.0" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      package_manager: "go_modules",
      requirements: [{
        file: "go.mod",
        requirement: dependency_version,
        groups: [],
        source: { type: "default", source: dependency_name }
      }]
    )
  end

  let(:go_mod_content) do
    <<~GOMOD
      module foobar
      require #{dependency_name} v#{dependency_version}
    GOMOD
  end

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "go.mod",
        content: go_mod_content
      )
    ]
  end

  describe "#latest_version" do
    context "when the latest version is an '+incompatible' version" do # https://golang.org/ref/mod#incompatible-versions
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-incompatible" }
      let(:dependency_version) { "2.0.0+incompatible" }

      it "returns the current version" do
        finder = described_class.new(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }],
          ignored_versions: []
        )

        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("2.0.0+incompatible"))
      end
    end
  end
end
