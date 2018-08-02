# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/update_checkers/go/dep/version_resolver"

RSpec.describe Dependabot::UpdateCheckers::Go::Dep::VersionResolver do
  subject(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Gopkg.toml",
        content: fixture("go", "gopkg_tomls", manifest_fixture_name)
      ),
      Dependabot::DependencyFile.new(
        name: "Gopkg.lock",
        content: fixture("go", "gopkg_locks", lockfile_fixture_name)
      )
    ]
  end
  let(:manifest_fixture_name) { "no_version.toml" }
  let(:lockfile_fixture_name) { "no_version.lock" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "cargo"
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "dep"
    )
  end
  let(:requirements) do
    [{ file: "Gopkg.toml", requirement: req_str, groups: [], source: source }]
  end
  let(:dependency_name) { "github.com/dgrijalva/jwt-go" }
  let(:dependency_version) { "1.0.1" }
  let(:req_str) { nil }
  let(:source) { { type: "default", source: "github.com/dgrijalva/jwt-go" } }

  describe "latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    it { is_expected.to be >= Gem::Version.new("0.3.0") }

    context "with a git dependency" do
      context "that specifies a branch" do
        let(:manifest_fixture_name) { "branch.toml" }
        let(:lockfile_fixture_name) { "branch.lock" }
        let(:dependency_name) { "golang.org/x/text" }
        let(:source) do
          {
            type: "git",
            url: "https://github.com/golang/text",
            branch: "master",
            ref: nil
          }
        end

        it { is_expected.to eq("96e34ec0e18a62a1e59880c7bf617b655efecb66") }
      end

      context "that is unreachable" do
        let(:manifest_fixture_name) { "unreachable_source.toml" }
        let(:lockfile_fixture_name) { "unreachable_source.lock" }
        let(:dependency_name) { "github.com/dependabot/private-go-dep" }
        let(:source) do
          {
            type: "git",
            url: "https://github.com/dependabot/private-go-dep",
            branch: "master",
            ref: nil
          }
        end

        it "raises a helpful error" do
          expect { latest_resolvable_version }.to raise_error do |error|
            expect(error).to be_a Dependabot::GitDependenciesNotReachable
            expect(error.dependency_urls).
              to eq(["https://github.com/dependabot/private-go-dep"])
          end
        end
      end

      context "that specifies a tag as a revision" do
        let(:manifest_fixture_name) { "tag_as_revision.toml" }
        let(:lockfile_fixture_name) { "tag_as_revision.lock" }
        let(:dependency_name) { "golang.org/x/text" }
        let(:source) do
          {
            type: "git",
            url: "https://github.com/golang/text",
            branch: nil,
            ref: "v0.2.0"
          }
        end

        it { is_expected.to eq("v0.2.0") }
      end
    end
  end
end
