# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/maven/file_parser/wrapper_mojo"

RSpec.describe Dependabot::Maven::FileParser::WrapperMojo do
  def make_properties_file(name, content)
    Dependabot::DependencyFile.new(name: name, content: content)
  end

  def fixture_content(filename)
    fixture("wrapper_files", filename)
  end

  describe ".load_properties" do
    subject(:props) { described_class.load_properties(content) }

    context "with only-script mode (≥ 3.3.4)" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-only-script.properties") }

      it "parses distributionUrl" do
        expect(props.distribution_url).to eq(
          "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip"
        )
      end

      it "parses distributionSha256Sum" do
        expect(props.distribution_sha256_sum).to eq("a555254d6b53d267965a3404ecb14e53c3827c09c3b94b5cdbba7861a1498407")
      end

      it "parses wrapperVersion" do
        expect(props.wrapper_version).to eq("3.3.4")
        expect(props.wrapper_replace).to eq("3.3.4")
      end

      it "parses distributionType" do
        expect(props.distribution_type).to eq("only-script")
      end
    end

    context "with bin mode (< 3.3.0)" do
      let(:content) { fixture_content("maven-wrapper-3.9.6-bin.properties") }

      it "strips \\: escapes from distribution_url" do
        expect(props.distribution_url).to eq(
          "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.6/apache-maven-3.9.6-bin.zip"
        )
      end

      it "preserves \\: in distribution_replace" do
        expect(props.distribution_replace).to include("\\:")
      end

      it "parses wrapperUrl for wrapper version" do
        expect(props.wrapper_version).to eq("3.2.0")
        expect(props.wrapper_replace).to include("maven-wrapper-3.2.0.jar")
      end

      it "defaults distributionType to bin" do
        expect(props.distribution_type).to eq("bin")
      end
    end

    context "with bin mode with checksum and explicit wrapperVersion" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-bin-checksum.properties") }

      it "prefers wrapperVersion over wrapperUrl" do
        expect(props.wrapper_version).to eq("3.3.4")
        expect(props.wrapper_replace).to eq("3.3.4")
      end
    end

    context "with no wrapperVersion (3.3.3 gap)" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-no-wrapper-version.properties") }

      it "returns nil for wrapper_version" do
        expect(props.wrapper_version).to be_nil
        expect(props.wrapper_replace).to be_nil
      end
    end

    context "with a pre-release version in distributionUrl" do
      let(:content) do
        "distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/" \
          "3.9.0-alpha-1/apache-maven-3.9.0-alpha-1-bin.zip\n" \
          "wrapperVersion=3.3.4\n"
      end

      it "parses the pre-release version from distributionUrl" do
        expect(props.distribution_url).to include("3.9.0-alpha-1")
      end

      it "sets distribution_replace to the full URL segment" do
        expect(props.distribution_replace).to include("apache-maven-3.9.0-alpha-1-bin.zip")
      end
    end

    context "with no distributionUrl line" do
      let(:content) { "wrapperVersion=3.3.4\ndistributionType=only-script\n" }

      it "returns nil for distribution_url" do
        expect(props.distribution_url).to be_nil
      end

      it "returns nil for distribution_replace" do
        expect(props.distribution_replace).to be_nil
      end
    end
  end

  describe ".distribution_type" do
    it "returns only-script for only-script mode" do
      content = fixture_content("maven-wrapper-3.9.9-only-script.properties")
      expect(described_class.distribution_type(content)).to eq("only-script")
    end

    it "returns source for source mode" do
      content = fixture_content("maven-wrapper-3.9.9-source.properties")
      expect(described_class.distribution_type(content)).to eq("source")
    end

    it "defaults to bin when property is absent" do
      content = fixture_content("maven-wrapper-3.9.6-bin.properties")
      expect(described_class.distribution_type(content)).to eq("bin")
    end
  end

  describe ".resolve_dependencies" do
    let(:properties_file) { make_properties_file(".mvn/wrapper/maven-wrapper.properties", content) }

    context "with only-script mode" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-only-script.properties") }

      it "returns two dependencies" do
        deps = described_class.resolve_dependencies(properties_file)
        expect(deps.length).to eq(2)
      end

      it "returns apache-maven dependency" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven:apache-maven" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("3.9.9")
        expect(dep.requirements.first[:source][:type]).to eq("maven-distribution")
        expect(dep.requirements.first[:source][:property]).to eq("distributionUrl")
      end

      it "returns maven-wrapper dependency" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven.wrapper:maven-wrapper" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("3.3.4")
        expect(dep.requirements.first[:source][:property]).to eq("wrapperVersion")
      end

      it "includes sha256 requirement on apache-maven" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven:apache-maven" }
        expect(dep.requirements.length).to eq(2)
        sha_req = dep.requirements.find { |r| r[:source][:property] == "distributionSha256Sum" }
        expect(sha_req).not_to be_nil
        expect(sha_req[:requirement]).to eq("a555254d6b53d267965a3404ecb14e53c3827c09c3b94b5cdbba7861a1498407")
      end
    end

    context "with bin mode (< 3.3.0)" do
      let(:content) { fixture_content("maven-wrapper-3.9.6-bin.properties") }

      it "returns maven-wrapper with wrapperUrl property" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven.wrapper:maven-wrapper" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("3.2.0")
        expect(dep.requirements.first[:source][:property]).to eq("wrapperUrl")
      end
    end

    context "with 3.3.0 gap (no wrapperVersion, no wrapperUrl)" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-no-wrapper-version.properties") }
      let(:script_content) { fixture("wrapper_files", "mvnw-3.3.0") }
      let(:mvnw_file) { make_properties_file("mvnw", script_content) }

      it "falls back to script comment for wrapper version" do
        deps = described_class.resolve_dependencies(properties_file, script_files: [mvnw_file])
        wrapper_dep = deps.find { |d| d.name == "org.apache.maven.wrapper:maven-wrapper" }
        expect(wrapper_dep).not_to be_nil
        expect(wrapper_dep.version).to eq("3.3.0")
        expect(wrapper_dep.requirements.first[:source][:property]).to eq("scriptVersion")
      end
    end

    context "with no script files and no wrapper version" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-no-wrapper-version.properties") }

      it "returns only the apache-maven dependency" do
        deps = described_class.resolve_dependencies(properties_file)
        expect(deps.length).to eq(1)
        expect(deps.first.name).to eq("org.apache.maven:apache-maven")
      end
    end

    context "with empty content" do
      let(:content) { "" }

      it "returns empty array" do
        expect(described_class.resolve_dependencies(properties_file)).to eq([])
      end
    end

    context "when distributionUrl does not contain the apache-maven path pattern" do
      let(:content) do
        "distributionUrl=https://example.com/custom/distro.zip\nwrapperVersion=3.3.4\n"
      end

      it "returns empty array" do
        expect(described_class.resolve_dependencies(properties_file)).to eq([])
      end
    end

    context "with source distribution type" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-source.properties") }

      it "returns two dependencies" do
        deps = described_class.resolve_dependencies(properties_file)
        expect(deps.length).to eq(2)
      end

      it "returns the apache-maven dependency" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven:apache-maven" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("3.9.9")
      end

      it "returns the maven-wrapper dependency" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven.wrapper:maven-wrapper" }
        expect(dep).not_to be_nil
        expect(dep.requirements.first[:source][:property]).to eq("wrapperVersion")
      end
    end

    context "with bin mode (wrapperUrl JAR)" do
      let(:content) { fixture_content("maven-wrapper-3.9.6-bin.properties") }

      it "sets wrapperUrl as the property for the maven-wrapper dependency" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven.wrapper:maven-wrapper" }
        expect(dep.requirements.first[:source][:property]).to eq("wrapperUrl")
      end

      it "stores the full JAR URL as replace_string" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven.wrapper:maven-wrapper" }
        expect(dep.requirements.first[:source][:replace_string]).to include("maven-wrapper-3.2.0.jar")
      end
    end

    context "with the apache-maven distribution dependency" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-only-script.properties") }

      it "sets packaging_type to pom in the requirement metadata" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven:apache-maven" }
        dist_req = dep.requirements.find { |r| r[:source][:property] == "distributionUrl" }
        expect(dist_req[:metadata]).to eq({ packaging_type: "pom" })
      end
    end
  end

  describe ".read_wrapper_options" do
    it "returns empty array when no debug scripts present" do
      Dir.mktmpdir do |dir|
        expect(described_class.read_wrapper_options(dir)).to eq([])
      end
    end

    it "returns -DincludeDebugScript=true when mvnwDebug is present" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "mvnwDebug"), "#!/bin/sh\n")
        expect(described_class.read_wrapper_options(dir)).to eq(["-DincludeDebugScript=true"])
      end
    end

    it "returns -DincludeDebugScript=true when mvnwDebug.cmd is present" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "mvnwDebug.cmd"), "@REM debug\n")
        expect(described_class.read_wrapper_options(dir)).to eq(["-DincludeDebugScript=true"])
      end
    end
  end
end
