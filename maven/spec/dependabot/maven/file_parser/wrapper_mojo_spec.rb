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
      end

      it "parses distributionType" do
        expect(props.distribution_type).to eq("only-script")
      end
    end

    context "with bin mode (< 3.3.0)" do
      let(:content) { fixture_content("maven-wrapper-3.9.6-bin.properties") }

      it "returns raw distribution_url with \\: escapes" do
        expect(props.distribution_url).to eq(
          "https\\://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.6/apache-maven-3.9.6-bin.zip"
        )
      end

      it "parses wrapperUrl for wrapper version" do
        expect(props.wrapper_version).to eq("3.2.0")
        expect(props.wrapper_url).to include("maven-wrapper-3.2.0.jar")
      end

      it "defaults distributionType to bin" do
        expect(props.distribution_type).to eq("bin")
      end
    end

    context "with bin mode with checksum and explicit wrapperVersion" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-bin-checksum.properties") }

      it "prefers wrapperVersion over wrapperUrl" do
        expect(props.wrapper_version).to eq("3.3.4")
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
    end

    context "with all properties present" do
      let(:dist_url) { "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip" }
      let(:wrap_url) { "https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.3.4/maven-wrapper-3.3.4.jar" }
      let(:dist_sha) { "a555254d6b53d267965a3404ecb14e53c3827c09c3b94b5cdbba7861a1498407" }
      let(:wrap_sha) { "e3b0c44298fc1c149afbf4c8996fb924" * 2 }
      let(:content) do
        "distributionUrl=#{dist_url}\n" \
          "distributionSha256Sum=#{dist_sha}\n" \
          "distributionType=bin\n" \
          "wrapperVersion=3.3.4\n" \
          "wrapperUrl=#{wrap_url}\n" \
          "wrapperSha256Sum=#{wrap_sha}\n"
      end

      it "parses distributionUrl" do
        expect(props.distribution_url).to eq(dist_url)
      end

      it "parses distribution_version from the URL path" do
        expect(props.distribution_version).to eq("3.9.9")
      end

      it "parses distributionSha256Sum" do
        expect(props.distribution_sha256_sum).to eq(dist_sha)
      end

      it "parses distributionType" do
        expect(props.distribution_type).to eq("bin")
      end

      it "parses wrapperVersion" do
        expect(props.wrapper_version).to eq("3.3.4")
      end

      it "parses wrapperUrl" do
        expect(props.wrapper_url).to include("maven-wrapper-3.3.4.jar")
      end

      it "parses wrapperSha256Sum" do
        expect(props.wrapper_sha256_sum).to eq(wrap_sha)
      end
    end

    context "with missing checksums" do
      let(:base_url) { "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip" }
      let(:content) { "distributionUrl=#{base_url}\ndistributionType=only-script\nwrapperVersion=3.3.4\n" }

      it "sets distribution_sha256_sum to nil" do
        expect(props.distribution_sha256_sum).to be_nil
      end

      it "sets wrapper_sha256_sum to nil" do
        expect(props.wrapper_sha256_sum).to be_nil
      end
    end

    context "with missing distributionType and wrapperVersion" do
      subject(:props) { described_class.load_properties(content, script_files: [mvnw_file]) }

      let(:content) do
        "distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip\n"
      end
      let(:script_content) { fixture("wrapper_files", "mvnw-3.3.0") }
      let(:mvnw_file) { make_properties_file("mvnw", script_content) }

      it "defaults distributionType to bin" do
        expect(props.distribution_type).to eq("bin")
      end

      it "reads wrapper_version from the script file" do
        expect(props.wrapper_version).to eq("3.3.0")
      end
    end

    context "when distributionUrl is missing" do
      let(:content) { "wrapperVersion=3.3.4\n" }

      it "raises a missing mandatory property error" do
        expect { props }.to raise_error(RuntimeError, /Missing mandatory property: distributionUrl/)
      end
    end

    context "when no wrapper version source is available" do
      let(:content) do
        "distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip\n"
      end

      it "raises an error about the unresolvable wrapper version" do
        expect { props }.to raise_error(RuntimeError, /Could not determine Maven Wrapper version/)
      end
    end
  end

  describe ".extract_distribution_version" do
    it "extracts the version from a standard bin zip URL" do
      url = "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip"
      expect(described_class.extract_distribution_version(url)).to eq("3.9.9")
    end

    it "extracts an alpha pre-release version" do
      url = "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.0-alpha-1/apache-maven-3.9.0-alpha-1-bin.zip"
      expect(described_class.extract_distribution_version(url)).to eq("3.9.0-alpha-1")
    end

    it "extracts an alpha pre-release version with a double-digit number" do
      url = "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/4.0.0-alpha-10/apache-maven-4.0.0-alpha-10-bin.zip"
      expect(described_class.extract_distribution_version(url)).to eq("4.0.0-alpha-10")
    end

    it "extracts a beta pre-release version" do
      url = "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/4.0.0-beta-3/apache-maven-4.0.0-beta-3-bin.zip"
      expect(described_class.extract_distribution_version(url)).to eq("4.0.0-beta-3")
    end

    it "extracts a release candidate version" do
      url = "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/4.0.0-rc-2/apache-maven-4.0.0-rc-2-bin.zip"
      expect(described_class.extract_distribution_version(url)).to eq("4.0.0-rc-2")
    end

    it "extracts the version from a tar.gz URL" do
      url = "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.8.6/apache-maven-3.8.6-bin.tar.gz"
      expect(described_class.extract_distribution_version(url)).to eq("3.8.6")
    end

    it "raises when the URL contains no recognizable version path segment" do
      expect { described_class.extract_distribution_version("https://example.com/some-artifact.zip") }
        .to raise_error(RuntimeError, /Could not extract Maven version from content/)
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
      end
    end

    context "with bin mode (< 3.3.0)" do
      let(:content) { fixture_content("maven-wrapper-3.9.6-bin.properties") }

      it "returns maven-wrapper with wrapperUrl property" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven.wrapper:maven-wrapper" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("3.2.0")
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
      end
    end

    context "when the distribution URL points to the Maven daemon (mvnd)" do
      let(:content) do
        "distributionUrl=https://archive.apache.org/dist/maven/mvnd/1.0.2/maven-mvnd-1.0.2-bin.zip\n" \
          "distributionType=bin\nwrapperVersion=3.3.4\n"
      end

      it "returns an empty array" do
        expect(described_class.resolve_dependencies(properties_file)).to eq([])
      end

      it "logs a warning that mvnd is not supported" do
        expect(Dependabot.logger).to receive(:warn)
          .with(/Maven daemon \(mvnd\) distribution is not supported/)
        described_class.resolve_dependencies(properties_file)
      end
    end

    context "when the wrapperUrl points to a Takari distribution" do
      let(:takari_url) { "https://repo.maven.apache.org/maven2/io/takari/maven-wrapper/0.5.6/maven-wrapper-0.5.6.jar" }
      let(:dist_url) do
        "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.6.3/apache-maven-3.6.3-bin.zip"
      end
      let(:content) { "distributionUrl=#{dist_url}\nwrapperUrl=#{takari_url}\n" }

      it "returns an empty array" do
        expect(described_class.resolve_dependencies(properties_file)).to eq([])
      end

      it "logs a warning that Takari is not supported" do
        expect(Dependabot.logger).to receive(:warn)
          .with(/Takari distribution is not supported/)
        described_class.resolve_dependencies(properties_file)
      end
    end

    context "with the apache-maven distribution dependency" do
      let(:content) { fixture_content("maven-wrapper-3.9.9-only-script.properties") }

      it "sets packaging_type to pom in the requirement metadata" do
        dep = described_class.resolve_dependencies(properties_file)
                             .find { |d| d.name == "org.apache.maven:apache-maven" }
        dist_req = dep.requirements.find { |r| r[:source][:property] == "distributionUrl" }
        expect(dist_req[:metadata]).to eq(
          {
            packaging_type: "pom",
            wrapper_version: "3.3.4",
            distribution_type: "only-script",
            distribution_version: "3.9.9",
            include_debug_script: false,
            distribution_sha256_sum: "a555254d6b53d267965a3404ecb14e53c3827c09c3b94b5cdbba7861a1498407"
          }
        )
      end
    end

    context "with wrapper checksum present" do
      let(:dist_url) { "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip" }
      let(:wrap_url) { "https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.3.4/maven-wrapper-3.3.4.jar" }
      let(:dist_sha) { "a555254d6b53d267965a3404ecb14e53c3827c09c3b94b5cdbba7861a1498407" }
      let(:wrap_sha) { "e3b0c44298fc1c149afbf4c8996fb924" * 2 }
      let(:content) do
        "distributionUrl=#{dist_url}\n" \
          "distributionSha256Sum=#{dist_sha}\n" \
          "wrapperVersion=3.3.4\n" \
          "wrapperUrl=#{wrap_url}\n" \
          "wrapperSha256Sum=#{wrap_sha}\n"
      end

      it "captures wrapper_sha256_sum in the wrapperUrl requirement metadata" do
        deps = described_class.resolve_dependencies(properties_file)
        wrapper_req = deps.find { |d| d.requirements.any? { |r| r[:source][:property] == "wrapperUrl" } }
                          &.requirements
                          &.find { |r| r[:source][:property] == "wrapperUrl" }
        expect(wrapper_req[:metadata]).to eq({ wrapper_sha256_sum: wrap_sha })
      end
    end
  end
end
