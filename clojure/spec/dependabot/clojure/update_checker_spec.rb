# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/clojure/update_checker"
require "dependabot/clojure/version"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Clojure::UpdateChecker do
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: project_dependency_files("lein"),
      credentials: credentials,
      ignored_versions: [],
      security_advisories: [],
      update_cooldown: cooldown_options
    )
  end
  let(:credentials) { [] }
  let(:cooldown_options) { nil }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "ring:ring-core",
      version: "1.9.6",
      requirements: [{ file: "project.clj", requirement: "1.9.6", groups: ["dependencies"], source: nil }],
      package_manager: "clojure"
    )
  end

  let(:clojars) { "https://repo.clojars.org/ring/ring-core" }
  let(:central) { "https://repo.maven.apache.org/maven2/ring/ring-core" }
  # Declared in the project.clj fixture.
  let(:private_repo) { "https://repo.example.com/maven/ring/ring-core" }
  let(:plugin_repo) { "https://plugins.example.com/repo/ring/ring-core" }

  before do
    [central, private_repo, plugin_repo].each do |repo|
      stub_request(:get, "#{repo}/maven-metadata.xml").to_return(status: 404)
      stub_request(:get, "#{repo}/").to_return(status: 404)
      stub_request(:head, %r{\A#{Regexp.escape(repo)}/}).to_return(status: 404)
    end
    stub_request(:get, "#{clojars}/maven-metadata.xml")
      .to_return(status: 200, body: fixture("maven_metadata", "ring_core.xml"))
    # Like Clojars, the listing has no release dates.
    listing = %(<pre><a href="1.11.0/">1.11.0/</a>  -  -\n<a href="1.12.2/">1.12.2/</a>  -  -</pre>)
    stub_request(:get, "#{clojars}/").to_return(status: 200, body: listing)
    stub_request(:head, %r{\A#{Regexp.escape(clojars)}/.*\.(jar|pom)\z}).to_return(status: 200)
  end

  it_behaves_like "an update checker"

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    it "finds the latest stable release on Clojars" do
      expect(latest_version).to eq(Dependabot::Clojure::Version.new("1.12.2"))
    end

    context "with cooldown" do
      let(:cooldown_options) { Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7) }

      before do
        stub_request(:head, "#{clojars}/1.12.2/ring-core-1.12.2.pom")
          .to_return(status: 200, headers: { "Last-Modified" => (Time.now - 86_400).httpdate })
        stub_request(:head, "#{clojars}/1.11.0/ring-core-1.11.0.pom")
          .to_return(status: 200, headers: { "Last-Modified" => (Time.now - (30 * 86_400)).httpdate })
      end

      it "uses the POM's Last-Modified date to skip recent releases" do
        expect(latest_version).to eq(Dependabot::Clojure::Version.new("1.11.0"))
      end
    end

    context "when Clojars is unavailable" do
      before { stub_request(:get, "#{clojars}/maven-metadata.xml").to_return(status: 503) }

      it "raises a registry error instead of reporting no versions" do
        expect { latest_version }.to raise_error(Dependabot::RegistryError, /503/)
      end
    end

    context "with a private registry" do
      let(:credentials) do
        [Dependabot::Credential.new(
          {
            "type" => "maven_repository",
            "url" => "https://repo.example.com/maven/",
            "username" => "user",
            "password" => "secret"
          }
        )]
      end
      let(:auth) { { "Authorization" => "Basic #{Base64.strict_encode64('user:secret')}" } }

      before do
        stub_request(:get, "#{private_repo}/maven-metadata.xml")
          .with(headers: auth)
          .to_return(
            status: 200,
            body: "<metadata><versioning><versions><version>2.0.0</version></versions></versioning></metadata>"
          )
        stub_request(:head, "#{private_repo}/2.0.0/ring-core-2.0.0.jar").with(headers: auth).to_return(status: 200)
      end

      it "authenticates and includes its versions" do
        expect(latest_version).to eq(Dependabot::Clojure::Version.new("2.0.0"))
      end
    end

    context "with a registry that replaces the base repositories" do
      let(:mirror) { "https://mirror.example.com/maven/ring/ring-core" }
      let(:credentials) do
        [Dependabot::Credential.new(
          { "type" => "maven_repository", "url" => "https://mirror.example.com/maven", "replaces-base" => true }
        )]
      end

      before do
        stub_request(:get, "#{mirror}/maven-metadata.xml")
          .to_return(status: 200, body: fixture("maven_metadata", "ring_core.xml"))
        stub_request(:get, "#{mirror}/").to_return(status: 404)
        stub_request(:head, %r{\A#{Regexp.escape(mirror)}/}).to_return(status: 200)
      end

      it "uses it instead of Maven Central and Clojars" do
        expect(latest_version).to eq(Dependabot::Clojure::Version.new("1.12.2"))
        expect(a_request(:get, /repo\.clojars\.org|repo\.maven\.apache\.org/)).not_to have_been_made
      end
    end
  end

  describe "security updates" do
    let(:checker) do
      described_class.new(
        dependency: dependency,
        dependency_files: project_dependency_files("lein"),
        credentials: [],
        ignored_versions: [],
        security_advisories: [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "ring:ring-core",
            package_manager: "clojure",
            vulnerable_versions: ["< 1.11.0"],
            safe_versions: [">= 1.11.0"]
          )
        ]
      )
    end

    it "flags the dependency as vulnerable" do
      expect(checker.vulnerable?).to be(true)
    end

    it "picks the lowest fixed version, not the latest" do
      expect(checker.lowest_security_fix_version).to eq(Dependabot::Clojure::Version.new("1.11.0"))
      expect(checker.updated_requirements.first.requirement).to eq("1.11.0")
    end
  end

  describe "#updated_requirements" do
    it "pins the new version" do
      expect(checker.updated_requirements.map(&:to_h)).to eq(
        [{
          file: "project.clj",
          requirement: "1.12.2",
          groups: ["dependencies"],
          source: { type: "maven_repo", url: "https://repo.clojars.org" }
        }]
      )
    end

    context "with a version range" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "ring:ring-core",
          version: nil,
          requirements: [{ file: "project.clj", requirement: "[1.9,2.0)", groups: ["dependencies"], source: nil }],
          package_manager: "clojure"
        )
      end

      it "leaves the range alone" do
        expect(checker.updated_requirements.first.requirement).to eq("[1.9,2.0)")
      end
    end
  end
end
