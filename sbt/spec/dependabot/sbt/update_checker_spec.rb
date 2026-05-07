# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/sbt/update_checker"
require "dependabot/sbt/version"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Sbt::UpdateChecker do
  let(:version_class) { Dependabot::Sbt::Version }
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
  let(:cooldown_options) { nil }
  let(:dependency_files) { [build_sbt] }
  let(:build_sbt) do
    Dependabot::DependencyFile.new(
      name: "build.sbt",
      content: fixture("buildfiles", "basic_build.sbt")
    )
  end

  let(:dependency_name) { "com.google.guava:guava" }
  let(:dependency_version) { "33.0.0-jre" }
  let(:dependency_requirements) do
    [{
      file: "build.sbt",
      requirement: "33.0.0-jre",
      groups: [],
      source: nil,
      metadata: nil
    }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "sbt"
    )
  end

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories,
      update_cooldown: cooldown_options
    )
  end

  let(:maven_central_metadata_url) do
    "https://repo.maven.apache.org/maven2/" \
      "com/google/guava/guava/maven-metadata.xml"
  end
  let(:maven_central_releases) do
    fixture("maven_metadata", "guava.xml")
  end
  let(:maven_central_version_files_url) do
    "https://repo.maven.apache.org/maven2/" \
      "com/google/guava/guava/33.4.0-jre/guava-33.4.0-jre.jar"
  end

  before do
    stub_request(:get, maven_central_metadata_url)
      .to_return(status: 200, body: maven_central_releases)
    stub_request(:get, "https://repo.maven.apache.org/maven2/com/google/guava/guava")
      .to_return(status: 404)
    stub_request(:head, maven_central_version_files_url)
      .to_return(status: 200)
  end

  it_behaves_like "an update checker"

  describe "#latest_version" do
    subject { checker.latest_version }

    it { is_expected.to eq(version_class.new("33.4.0-jre")) }

    context "when the latest version hasn't been released" do
      before do
        stub_request(:head, maven_central_version_files_url)
          .to_return(status: 404)
        stub_request(
          :head,
          "https://repo.maven.apache.org/maven2/" \
          "com/google/guava/guava/33.3.0-jre/guava-33.3.0-jre.jar"
        ).to_return(status: 200)
      end

      it { is_expected.to eq(version_class.new("33.3.0-jre")) }
    end

    context "with a cross-versioned dependency" do
      let(:dependency_name) { "org.typelevel:cats-core_2.13" }
      let(:dependency_version) { "2.10.0" }
      let(:dependency_requirements) do
        [{
          file: "build.sbt",
          requirement: "2.10.0",
          groups: [],
          source: nil,
          metadata: { packaging_type: "cross-versioned" }
        }]
      end

      let(:maven_central_metadata_url) do
        "https://repo.maven.apache.org/maven2/" \
          "org/typelevel/cats-core_2.13/maven-metadata.xml"
      end
      let(:maven_central_releases) do
        fixture("maven_metadata", "cats_core_2.13.xml")
      end
      let(:maven_central_version_files_url) do
        "https://repo.maven.apache.org/maven2/" \
          "org/typelevel/cats-core_2.13/2.12.0/cats-core_2.13-2.12.0.jar"
      end

      it { is_expected.to eq(version_class.new("2.12.0")) }
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    it { is_expected.to eq(version_class.new("33.4.0-jre")) }

    context "when the version comes from a multi-dependency property" do
      let(:build_sbt) do
        Dependabot::DependencyFile.new(
          name: "build.sbt",
          content: fixture("buildfiles", "val_based_build.sbt")
        )
      end
      let(:dependency_name) { "org.typelevel:cats-core_2.13" }
      let(:dependency_version) { "2.10.0" }
      let(:dependency_requirements) do
        [{
          file: "build.sbt",
          requirement: "2.10.0",
          groups: [],
          source: nil,
          metadata: { property_name: "catsVersion", property_source: "build.sbt" }
        }]
      end

      before do
        stub_request(:get, "https://repo.maven.apache.org/maven2/org/typelevel/cats-core_2.13/maven-metadata.xml")
          .to_return(status: 200, body: fixture("maven_metadata", "cats_core_2.13.xml"))
        stub_request(:get, "https://repo.maven.apache.org/maven2/org/typelevel/cats-core_2.13")
          .to_return(status: 404)
        stub_request(:head, "https://repo.maven.apache.org/maven2/org/typelevel/cats-core_2.13/2.12.0/cats-core_2.13-2.12.0.jar")
          .to_return(status: 200)
      end

      # catsVersion is only used by cats-core in val_based_build.sbt, so it's NOT multi-dep
      it { is_expected.to eq(version_class.new("2.12.0")) }
    end
  end

  describe "#lowest_security_fix_version" do
    subject { checker.lowest_security_fix_version }

    let(:dependency_version) { "33.0.0-jre" }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "sbt",
          vulnerable_versions: ["< 33.2.0-jre"]
        )
      ]
    end

    before do
      stub_request(
        :head,
        "https://repo.maven.apache.org/maven2/" \
        "com/google/guava/guava/33.2.0-jre/guava-33.2.0-jre.jar"
      ).to_return(status: 200)
    end

    it { is_expected.to eq(version_class.new("33.2.0-jre")) }
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject { checker.latest_resolvable_version_with_no_unlock }

    it { is_expected.to be_nil }
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    it "updates the requirement version" do
      expect(updated_requirements).to eq(
        [{
          file: "build.sbt",
          requirement: "33.4.0-jre",
          groups: [],
          source: { type: "maven_repo", url: "https://repo.maven.apache.org/maven2" },
          metadata: nil
        }]
      )
    end
  end

  describe "#requirements_unlocked_or_can_be?" do
    subject { checker.requirements_unlocked_or_can_be? }

    it { is_expected.to be(true) }
  end
end
