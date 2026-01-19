# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/security_advisory"
require "dependabot/uv/update_checker/lock_file_resolver"

RSpec.describe Dependabot::Uv::UpdateChecker::LockFileResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      repo_contents_path: nil,
      security_advisories: security_advisories,
      ignored_versions: ignored_versions
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

  let(:security_advisories) { [] }
  let(:ignored_versions) { [] }

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "uv.lock",
        content: fixture("uv_locks", "simple.lock")
      ),
      Dependabot::DependencyFile.new(
        name: "pyproject.toml",
        content: fixture("pyproject_files", "uv_simple.toml")
      )
    ]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "requests",
      version: "2.32.3",
      requirements: [{
        file: "uv.lock",
        requirement: ">=2.31.0",
        groups: [],
        source: nil
      }],
      package_manager: "uv"
    )
  end

  describe "#latest_resolvable_version" do
    context "when requirement is nil" do
      it "returns nil" do
        expect(resolver.latest_resolvable_version(requirement: nil)).to be_nil
      end
    end

    context "when requirement is satisfied by the current version" do
      it "returns the current version" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0")
        expect(result.to_s).to eq("2.32.3")
      end
    end

    context "when requirement is not satisfied by the current version" do
      it "returns nil" do
        result = resolver.latest_resolvable_version(requirement: ">=3.0.0")
        expect(result).to be_nil
      end
    end
  end

  describe "#resolvable?" do
    it "returns true for any version" do
      expect(resolver.resolvable?(version: "2.32.3")).to be(true)
      expect(resolver.resolvable?(version: "999.0.0")).to be(true)
    end
  end

  describe "#lowest_resolvable_security_fix_version" do
    let(:pypi_url) { "https://pypi.org/simple/requests/" }
    let(:pypi_response) do
      fixture("pypi", "pypi_simple_response_requests.html")
    end

    before do
      stub_request(:get, pypi_url)
        .to_return(status: 200, body: pypi_response)
    end

    context "with no security advisories" do
      let(:security_advisories) { [] }

      it "returns nil when there are no advisories" do
        expect(resolver.lowest_resolvable_security_fix_version).to be_nil
      end
    end

    context "with a security advisory" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.0.0",
          requirements: [{
            file: "uv.lock",
            requirement: ">=2.0.0",
            groups: [],
            source: nil
          }],
          package_manager: "uv"
        )
      end

      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "requests",
            package_manager: "uv",
            vulnerable_versions: ["<= 2.1.0"]
          )
        ]
      end

      it "returns the lowest non-vulnerable version" do
        result = resolver.lowest_resolvable_security_fix_version
        expect(result).not_to be_nil
        expect(result).to be_a(Dependabot::Uv::Version)
        # Should return a version > 2.1.0
        expect(result).to be > Dependabot::Uv::Version.new("2.1.0")
      end
    end

    context "with multiple security advisories" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "1.0.0",
          requirements: [{
            file: "uv.lock",
            requirement: ">=1.0.0",
            groups: [],
            source: nil
          }],
          package_manager: "uv"
        )
      end

      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "requests",
            package_manager: "uv",
            vulnerable_versions: ["< 2.0.0"]
          ),
          Dependabot::SecurityAdvisory.new(
            dependency_name: "requests",
            package_manager: "uv",
            vulnerable_versions: ["< 2.5.0"]
          )
        ]
      end

      it "returns the lowest version that fixes all advisories" do
        result = resolver.lowest_resolvable_security_fix_version
        expect(result).not_to be_nil
        expect(result).to be_a(Dependabot::Uv::Version)
        # Should return a version >= 2.5.0
        expect(result).to be >= Dependabot::Uv::Version.new("2.5.0")
      end
    end

    context "with ignored versions" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "1.0.0",
          requirements: [{
            file: "uv.lock",
            requirement: ">=1.0.0",
            groups: [],
            source: nil
          }],
          package_manager: "uv"
        )
      end

      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "requests",
            package_manager: "uv",
            vulnerable_versions: ["< 2.0.0"]
          )
        ]
      end
      let(:ignored_versions) { [">= 2.30.0"] }

      it "respects ignored versions when finding security fix" do
        result = resolver.lowest_resolvable_security_fix_version
        expect(result).not_to be_nil
        # Should return a version < 2.30.0
        expect(result).to be < Dependabot::Uv::Version.new("2.30.0")
      end
    end
  end
end
