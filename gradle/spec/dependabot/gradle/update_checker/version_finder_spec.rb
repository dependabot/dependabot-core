# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/gradle/update_checker/version_finder"

RSpec.describe Dependabot::Gradle::UpdateChecker::VersionFinder do
  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories
    )
  end
  let(:version_class) { Dependabot::Gradle::Version }
  let(:credentials) { [] }
  let(:ignored_versions) { [] }
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
    "https://repo.maven.apache.org/maven2/"\
    "com/google/guava/guava/maven-metadata.xml"
  end
  let(:maven_central_releases) do
    fixture("maven_central_metadata", "with_release.xml")
  end

  before do
    stub_request(:get, maven_central_metadata_url).
      to_return(status: 200, body: maven_central_releases)
  end

  describe "#latest_version_details" do
    subject { finder.latest_version_details }
    its([:version]) { is_expected.to eq(version_class.new("23.6-jre")) }
    its([:source_url]) do
      is_expected.to eq("https://repo.maven.apache.org/maven2")
    end

    context "when the user wants a pre-release" do
      let(:dependency_version) { "23.0-rc1-android" }
      its([:version]) do
        is_expected.to eq(version_class.new("23.7-rc1-android"))
      end
    end

    context "when there are date-based versions" do
      let(:maven_central_releases) do
        fixture("maven_central_metadata", "with_date_releases.xml")
      end
      let(:dependency_version) { "3.1" }
      its([:version]) { is_expected.to eq(version_class.new("3.2.2")) }

      context "and that's what we're using" do
        let(:dependency_version) { "20030418" }
        its([:version]) { is_expected.to eq(version_class.new("20040616")) }
      end
    end

    context "when the user has asked to ignore a major version" do
      let(:ignored_versions) { [">= 23.0, < 24"] }
      let(:dependency_version) { "17.0" }
      its([:version]) { is_expected.to eq(version_class.new("22.0")) }
    end

    context "when the current version isn't normal" do
      let(:dependency_version) { "RELEASE802" }
      its([:version]) { is_expected.to eq(version_class.new("23.0")) }
    end

    context "with a custom repository" do
      let(:buildfile_fixture_name) { "custom_repos_build.gradle" }

      let(:jcenter_metadata_url) do
        "https://jcenter.bintray.com/"\
        "com/google/guava/guava/maven-metadata.xml"
      end

      let(:magnusja_metadata_url) do
        "https://dl.bintray.com/magnusja/maven/"\
        "com/google/guava/guava/maven-metadata.xml"
      end

      let(:google_metadata_url) do
        "https://maven.google.com/"\
        "com/google/guava/group-index.xml"
      end

      let(:dependency_version) { "18.0.0" }

      before do
        stub_request(:get, jcenter_metadata_url).
          to_return(status: 404, body: "")
        stub_request(:get, magnusja_metadata_url).
          to_raise(Excon::Error::Timeout)
        stub_request(:get, google_metadata_url).
          to_return(
            status: 200,
            body: fixture("google_metadata", "com_google_guava.xml")
          )
      end

      its([:version]) { is_expected.to eq(version_class.new("27.1.1")) }
      its([:source_url]) do
        is_expected.to eq("https://maven.google.com")
      end
    end

    context "with a repository from credentials" do
      let(:credentials) do
        [{
           "type" => "maven_repository",
           "url" => "https://private.registry.org/repo/",
           "username" => "dependabot",
           "password" => "dependabotPassword"
         }]
      end

      let(:private_registry_metadata_url) do
        "https://private.registry.org/repo/"\
        "com/google/guava/guava/maven-metadata.xml"
      end

      before do
        stub_request(:get, maven_central_metadata_url).
          to_return(status: 404)
        stub_request(:get, private_registry_metadata_url).
          with(basic_auth: %w(dependabot dependabotPassword)).
          to_return(status: 200, body: maven_central_releases)
      end

      its([:version]) { is_expected.to eq(version_class.new("23.6-jre")) }
      its([:source_url]) do
        is_expected.to eq("https://private.registry.org/repo")
      end

      context "but no auth details" do
        let(:credentials) do
          [{
             "type" => "maven_repository",
             "url" => "https://private.registry.org/repo/"
           }]
        end

        before do
          stub_request(:get, private_registry_metadata_url).
            to_return(status: 200, body: maven_central_releases)
        end

        its([:version]) { is_expected.to eq(version_class.new("23.6-jre")) }
        its([:source_url]) do
          is_expected.to eq("https://private.registry.org/repo")
        end

        context "when credentials are required" do
          before do
            stub_request(:get, private_registry_metadata_url).
              to_return(status: 401, body: "no dice")
          end

          it "raises a helpful error" do
            error_class = Dependabot::PrivateSourceAuthenticationFailure
            expect { subject }.
              to raise_error(error_class) do |error|
              expect(error.source).to eq("https://private.registry.org/repo")
            end
          end
        end
      end
    end

    context "with a plugin from credentials" do
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

      let(:private_plugin_registry_metadata_url) do
        "https://private.registry.org/repo/org/springframework/boot/"\
        "org.springframework.boot.gradle.plugin/maven-metadata.xml"
      end
      let(:gradle_plugin_releases) do
        fixture("gradle_plugin_metadata", "org_springframework_boot.xml")
      end
      let(:maven_metadata_url) do
        "https://plugins.gradle.org/m2/org/springframework/boot/"\
        "org.springframework.boot.gradle.plugin/maven-metadata.xml"
      end

      context "with credentials" do
        let(:credentials) do
          [{
             "type" => "maven_repository",
             "url" => "https://private.registry.org/repo/",
             "username" => "dependabot",
             "password" => "dependabotPassword"
           }]
        end

        before do
          stub_request(:get, maven_metadata_url).
            to_return(status: 404)
          stub_request(:get, private_plugin_registry_metadata_url).
            with(basic_auth: %w(dependabot dependabotPassword)).
            to_return(status: 200, body: gradle_plugin_releases)
        end

        its([:version]) { is_expected.to eq(version_class.new("2.1.4.RELEASE")) }
        its([:source_url]) do
          is_expected.to eq("https://private.registry.org/repo")
        end
      end

      context "no auth details" do
        let(:credentials) do
          [{
             "type" => "maven_repository",
             "url" => "https://private.registry.org/repo/"
           }]
        end

        before do
          stub_request(:get, maven_metadata_url).
            to_return(status: 404)
          stub_request(:get, private_plugin_registry_metadata_url).
            to_return(status: 200, body: gradle_plugin_releases)
        end

        its([:version]) { is_expected.to eq(version_class.new("2.1.4.RELEASE")) }
        its([:source_url]) do
          is_expected.to eq("https://private.registry.org/repo")
        end
      end

      context "when credentials are required" do
        let(:credentials) do
          [{
             "type" => "maven_repository",
             "url" => "https://private.registry.org/repo/"
           }]
        end
        before do
          stub_request(:get, maven_metadata_url).
            to_return(status: 404)
          stub_request(:get, private_plugin_registry_metadata_url).
            to_return(status: 401, body: "no dice")
        end

        it "raises a helpful error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { subject }.
            to raise_error(error_class) do |error|
            expect(error.source).to eq("https://private.registry.org/repo")
          end
        end
      end
    end
  end

  describe "#lowest_security_fix_version_details" do
    subject { finder.lowest_security_fix_version_details }

    let(:dependency_version) { "18.0" }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: "rails",
          package_manager: "gradle",
          safe_versions: ["> 19.0"]
        )
      ]
    end

    its([:version]) { is_expected.to eq(version_class.new("20.0")) }
    its([:source_url]) do
      is_expected.to eq("https://repo.maven.apache.org/maven2")
    end
  end

  describe "#versions" do
    subject(:versions) { finder.versions }
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
        "https://plugins.gradle.org/m2/org/springframework/boot/"\
        "org.springframework.boot.gradle.plugin/maven-metadata.xml"
      end
      let(:gradle_plugin_releases) do
        fixture("gradle_plugin_metadata", "org_springframework_boot.xml")
      end
      let(:maven_metadata_url) do
        "https://repo.maven.apache.org/maven2/org/springframework/boot/"\
        "org.springframework.boot.gradle.plugin/maven-metadata.xml"
      end

      before do
        stub_request(:get, gradle_plugin_metadata_url).
          to_return(status: 200, body: gradle_plugin_releases)
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

    context "with a custom repository" do
      let(:buildfile_fixture_name) { "custom_repos_build.gradle" }

      let(:jcenter_metadata_url) do
        "https://jcenter.bintray.com/"\
        "com/google/guava/guava/maven-metadata.xml"
      end

      let(:magnusja_metadata_url) do
        "https://dl.bintray.com/magnusja/maven/"\
        "com/google/guava/guava/maven-metadata.xml"
      end

      let(:google_metadata_url) do
        "https://maven.google.com/"\
        "com/google/guava/group-index.xml"
      end

      before do
        stub_request(:get, jcenter_metadata_url).
          to_return(status: 404, body: "")
        stub_request(:get, magnusja_metadata_url).
          to_raise(Excon::Error::Timeout)
        stub_request(:get, google_metadata_url).
          to_return(
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
          "https://jcenter.bintray.com/"\
          "com/google/guava/guava~bad/maven-metadata.xml"
        end
        let(:magnusja_metadata_url) do
          "https://dl.bintray.com/magnusja/maven/"\
          "com/google/guava/guava~bad/maven-metadata.xml"
        end
        let(:google_metadata_url) do
          "https://maven.google.com/"\
          "com/google/guava/group-index.xml"
        end

        before do
          stub_request(:get, google_metadata_url).
            to_return(status: 404, body: "")
        end

        it { is_expected.to eq([]) }
      end

      context "when the details come from a non-google repo" do
        before do
          stub_request(:get, jcenter_metadata_url).
            to_return(
              status: 200,
              body:
                fixture("maven_central_metadata", "with_release.xml")
            )
          stub_request(:get, magnusja_metadata_url).
            to_raise(Excon::Error::Timeout)
          stub_request(:get, google_metadata_url).
            to_return(status: 404, body: "")
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
