# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/sbt/file_parser/repositories_finder"

RSpec.describe Dependabot::Sbt::FileParser::RepositoriesFinder do
  subject(:finder) do
    described_class.new(
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:credentials) { [] }
  let(:dependency_files) { [build_sbt] }

  let(:build_sbt) do
    Dependabot::DependencyFile.new(
      name: "build.sbt",
      content: build_sbt_content
    )
  end

  describe "#repository_urls" do
    context "when no custom resolvers are declared" do
      let(:build_sbt_content) do
        <<~SBT
          scalaVersion := "2.13.12"
          libraryDependencies += "org.typelevel" %% "cats-core" % "2.10.0"
        SBT
      end

      it "returns the central repository" do
        expect(finder.repository_urls).to eq(
          ["https://repo.maven.apache.org/maven2"]
        )
      end
    end

    context "with resolvers += ... at ... syntax" do
      let(:build_sbt_content) do
        <<~SBT
          resolvers += "Sonatype OSS" at "https://oss.sonatype.org/content/repositories/releases"
          resolvers += "Artima" at "https://repo.artima.com/releases"
        SBT
      end

      it "returns all declared resolver URLs" do
        expect(finder.repository_urls).to contain_exactly(
          "https://oss.sonatype.org/content/repositories/releases",
          "https://repo.artima.com/releases"
        )
      end
    end

    context "with resolvers ++= Seq(...) syntax" do
      let(:build_sbt_content) do
        <<~SBT
          resolvers ++= Seq(
            "Sonatype OSS" at "https://oss.sonatype.org/content/repositories/releases",
            "Artima" at "https://repo.artima.com/releases"
          )
        SBT
      end

      it "returns all resolver URLs from the Seq block" do
        expect(finder.repository_urls).to contain_exactly(
          "https://oss.sonatype.org/content/repositories/releases",
          "https://repo.artima.com/releases"
        )
      end
    end

    context "with Resolver.url(...) syntax" do
      let(:build_sbt_content) do
        <<~SBT
          resolvers += Resolver.url("my-repo", url("https://dl.bintray.com/my/repo"))
        SBT
      end

      it "returns the resolver URL" do
        expect(finder.repository_urls).to eq(
          ["https://dl.bintray.com/my/repo"]
        )
      end
    end

    context "with MavenRepository(...) syntax" do
      let(:build_sbt_content) do
        <<~SBT
          resolvers += MavenRepository("my-repo", "https://maven.example.com/releases")
        SBT
      end

      it "returns the Maven repository URL" do
        expect(finder.repository_urls).to eq(
          ["https://maven.example.com/releases"]
        )
      end
    end

    context "with mixed resolver styles" do
      let(:build_sbt_content) do
        <<~SBT
          resolvers += "Sonatype" at "https://oss.sonatype.org/releases"
          resolvers += Resolver.url("bintray", url("https://dl.bintray.com/repo"))
          resolvers += MavenRepository("custom", "https://maven.example.com/releases")
        SBT
      end

      it "returns all unique resolver URLs" do
        expect(finder.repository_urls).to contain_exactly(
          "https://oss.sonatype.org/releases",
          "https://dl.bintray.com/repo",
          "https://maven.example.com/releases"
        )
      end
    end

    context "with commented-out resolvers" do
      let(:build_sbt_content) do
        <<~SBT
          // resolvers += "Old" at "https://old.example.com/releases"
          resolvers += "Active" at "https://active.example.com/releases"
        SBT
      end

      it "ignores commented-out resolvers" do
        expect(finder.repository_urls).to eq(
          ["https://active.example.com/releases"]
        )
      end
    end

    context "with duplicate resolver URLs" do
      let(:build_sbt_content) do
        <<~SBT
          resolvers += "Repo1" at "https://oss.sonatype.org/releases"
          resolvers += "Repo2" at "https://oss.sonatype.org/releases"
        SBT
      end

      it "deduplicates URLs" do
        expect(finder.repository_urls).to eq(
          ["https://oss.sonatype.org/releases"]
        )
      end
    end

    context "with trailing slashes on URLs" do
      let(:build_sbt_content) do
        <<~SBT
          resolvers += "Repo" at "https://oss.sonatype.org/releases/"
        SBT
      end

      it "strips trailing slashes" do
        expect(finder.repository_urls).to eq(
          ["https://oss.sonatype.org/releases"]
        )
      end
    end

    context "with a replaces-base credential" do
      let(:build_sbt_content) { "" }

      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "maven_repository",
              "url" => "https://private.example.com/maven/",
              "replaces-base" => true
            }
          )
        ]
      end

      it "uses the credential URL instead of Maven Central" do
        expect(finder.repository_urls).to eq(
          ["https://private.example.com/maven"]
        )
      end
    end

    context "with multiple build files" do
      let(:sub_build_sbt) do
        Dependabot::DependencyFile.new(
          name: "sub/build.sbt",
          content: 'resolvers += "Sub" at "https://sub.example.com/releases"'
        )
      end

      let(:build_sbt_content) do
        'resolvers += "Root" at "https://root.example.com/releases"'
      end

      let(:dependency_files) { [build_sbt, sub_build_sbt] }

      it "collects resolvers from all build files" do
        expect(finder.repository_urls).to contain_exactly(
          "https://root.example.com/releases",
          "https://sub.example.com/releases"
        )
      end
    end
  end
end
