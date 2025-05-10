# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/gradle/update_checker/version_finder"

RSpec.describe Dependabot::Gradle::Package::PackageDetailsFetcher do
  let(:packagedetailsfetcher) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,

      forbidden_urls: []
    )
  end
  let(:version_class) { Dependabot::Gradle::Version }
  let(:credentials) { [] }
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
  let(:security_advisories) { [] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "gradle"
    )
  end
  let(:dependency_files) { [buildfile] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "basic_build.gradle" }

  let(:dependency_requirements) do
    [{ file: "build.gradle", requirement: "23.3-jre", groups: [], source: nil }]
  end
  let(:dependency_name) { "com.google.guava:guava" }
  let(:dependency_version) { "23.3-jre" }

  let(:maven_central_metadata_url) do
    "https://repo.maven.apache.org/maven2/" \
      "com/google/guava/guava/maven-metadata.xml"
  end
  let(:maven_central_releases) do
    fixture("maven_central_metadata", "with_release.xml")
  end

  before do
    stub_request(:get, maven_central_metadata_url)
      .to_return(status: 200, body: maven_central_releases)
  end

  describe "#versions" do
    subject(:versions) { packagedetailsfetcher.fetch_available_versions }

    its(:count) { is_expected.to eq(70) }

    describe "the first version" do
      subject { versions.first }

      its([:version]) { is_expected.to eq(version_class.new("r03")) }

      its([:source_url]) do
        is_expected.to eq("https://repo.maven.apache.org/maven2")
      end
    end

    describe "the last version" do
      subject { versions.last }

      its([:version]) { is_expected.to eq(version_class.new("23.7-rc1-jre")) }

      its([:source_url]) do
        is_expected.to eq("https://repo.maven.apache.org/maven2")
      end
    end

    context "with a plugin" do
      let(:dependency_requirements) do
        [{
          file: "build.gradle",
          requirement: "2.0.5.RELEASE",
          groups: ["plugins"],
          source: nil
        }]
      end
      let(:dependency_name) { "org.springframework.boot" }
      let(:dependency_version) { "2.0.5.RELEASE" }

      let(:gradle_plugin_metadata_url) do
        "https://plugins.gradle.org/m2/org/springframework/boot/" \
          "org.springframework.boot.gradle.plugin/maven-metadata.xml"
      end
      let(:gradle_plugin_releases) do
        fixture("gradle_plugin_metadata", "org_springframework_boot.xml")
      end
      let(:maven_metadata_url) do
        "https://repo.maven.apache.org/maven2/org/springframework/boot/" \
          "org.springframework.boot.gradle.plugin/maven-metadata.xml"
      end

      before do
        stub_request(:get, gradle_plugin_metadata_url)
          .to_return(status: 200, body: gradle_plugin_releases)
        stub_request(:get, maven_metadata_url).to_return(status: 404)
      end

      describe "the first version" do
        subject { versions.first }

        its([:version]) do
          is_expected.to eq(version_class.new("1.4.2.RELEASE"))
        end

        its([:source_url]) do
          is_expected.to eq("https://plugins.gradle.org/m2")
        end
      end

      describe "the last version" do
        subject { versions.last }

        its([:version]) do
          is_expected.to eq(version_class.new("2.1.4.RELEASE"))
        end

        its([:source_url]) do
          is_expected.to eq("https://plugins.gradle.org/m2")
        end
      end
    end

    context "with a kotlin plugin" do
      let(:dependency_requirements) do
        [{
          file: "build.gradle",
          requirement: "1.4.10",
          groups: %w(plugins kotlin),
          source: nil
        }]
      end
      let(:dependency_name) { "jvm" }
      let(:dependency_version) { "1.4.10" }

      let(:gradle_plugin_metadata_url) do
        "https://plugins.gradle.org/m2/org/jetbrains/kotlin/jvm/" \
          "org.jetbrains.kotlin.jvm.gradle.plugin/maven-metadata.xml"
      end
      let(:gradle_plugin_releases) do
        fixture("gradle_plugin_metadata", "org_jetbrains_kotlin_jvm.xml")
      end
      let(:maven_metadata_url) do
        "https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/jvm/" \
          "org.jetbrains.kotlin.jvm.gradle.plugin/maven-metadata.xml"
      end

      before do
        stub_request(:get, gradle_plugin_metadata_url)
          .to_return(status: 200, body: gradle_plugin_releases)
        stub_request(:get, maven_metadata_url).to_return(status: 404)
      end

      describe "the first version" do
        subject { versions.first }

        its([:version]) do
          is_expected.to eq(version_class.new("0.0.1-test-1"))
        end

        its([:source_url]) do
          is_expected.to eq("https://plugins.gradle.org/m2")
        end
      end

      describe "the last version" do
        subject { versions.last }

        its([:version]) do
          is_expected.to eq(version_class.new("1.4.30-M1"))
        end

        its([:source_url]) do
          is_expected.to eq("https://plugins.gradle.org/m2")
        end
      end
    end

    context "with a custom repository" do
      let(:buildfile_fixture_name) { "custom_repos_build.gradle" }

      let(:jcenter_metadata_url) do
        "https://jcenter.bintray.com/" \
          "com/google/guava/guava/maven-metadata.xml"
      end

      let(:magnusja_metadata_url) do
        "https://dl.bintray.com/magnusja/maven/" \
          "com/google/guava/guava/maven-metadata.xml"
      end

      let(:google_metadata_url) do
        "https://maven.google.com/" \
          "com/google/guava/group-index.xml"
      end

      before do
        stub_request(:get, jcenter_metadata_url)
          .to_return(status: 404, body: "")
        stub_request(:get, magnusja_metadata_url)
          .to_raise(Excon::Error::Timeout)
        stub_request(:get, google_metadata_url)
          .to_return(
            status: 200,
            body: fixture("google_metadata", "com_google_guava.xml")
          )
      end

      describe "the first version" do
        subject { versions.first }

        its([:version]) { is_expected.to eq(version_class.new("18.0.0")) }
        its([:source_url]) { is_expected.to eq("https://maven.google.com") }
      end

      describe "the last version" do
        subject { versions.last }

        its([:version]) do
          is_expected.to eq(version_class.new("28.0.0-alpha1"))
        end

        its([:source_url]) { is_expected.to eq("https://maven.google.com") }
      end

      context "with a name that can't be an xpath" do
        let(:dependency_name) { "com.google.guava:guava~bad" }
        let(:jcenter_metadata_url) do
          "https://jcenter.bintray.com/" \
            "com/google/guava/guava~bad/maven-metadata.xml"
        end
        let(:magnusja_metadata_url) do
          "https://dl.bintray.com/magnusja/maven/" \
            "com/google/guava/guava~bad/maven-metadata.xml"
        end
        let(:google_metadata_url) do
          "https://maven.google.com/" \
            "com/google/guava/group-index.xml"
        end

        before do
          stub_request(:get, google_metadata_url)
            .to_return(status: 404, body: "")
        end

        it { is_expected.to eq([]) }
      end

      context "when the details come from a non-google repo" do
        before do
          stub_request(:get, jcenter_metadata_url)
            .to_return(
              status: 200,
              body:
                fixture("maven_central_metadata", "with_release.xml")
            )
          stub_request(:get, magnusja_metadata_url)
            .to_raise(Excon::Error::Timeout)
          stub_request(:get, google_metadata_url)
            .to_return(status: 404, body: "")
        end

        describe "the last version" do
          subject { versions.last }

          its([:version]) do
            is_expected.to eq(version_class.new("23.7-rc1-jre"))
          end

          its([:source_url]) do
            is_expected.to eq("https://jcenter.bintray.com")
          end
        end
      end
    end
  end
end
