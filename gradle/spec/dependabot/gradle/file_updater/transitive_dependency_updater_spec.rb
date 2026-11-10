# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/experiments"
require "dependabot/gradle/file_parser"
require "dependabot/gradle/update_checker"
require "dependabot/gradle/file_updater"
require "dependabot/gradle/metadata_finder"

RSpec.describe Dependabot::Gradle::FileUpdater::TransitiveDependencyUpdater do
  extend T::Sig

  # Keep signatures attached to their RSpec declarations.
  # rubocop:disable RSpec/ScatteredLet
  sig { returns(String) }
  let(:project_path) { File.expand_path("../../../fixtures/projects/transitive_security", __dir__) }

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:files) do
    %w(build.gradle settings.gradle gradle.lockfile).map do |name|
      Dependabot::DependencyFile.new(name: name, content: File.read(File.join(project_path, name)))
    end
  end

  sig { returns(Dependabot::Gradle::FileParser) }
  let(:parser) { Dependabot::Gradle::FileParser.new(dependency_files: files, source: nil) }

  sig { returns(Dependabot::Dependency) }
  let(:dependency) { T.must(parser.parse.find { |dep| dep.name == "org.example:child" }) }

  sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
  let(:advisories) do
    [Dependabot::SecurityAdvisory.new(
      dependency_name: "org.example:child",
      package_manager: "gradle",
      vulnerable_versions: [Dependabot::Gradle::Requirement.new("< 1.1")]
    )]
  end

  sig { returns(Dependabot::Gradle::UpdateChecker) }
  let(:checker) do
    Dependabot::Gradle::UpdateChecker.new(
      dependency: dependency,
      dependency_files: files,
      credentials: [],
      security_advisories: advisories,
      repo_contents_path: project_path
    )
  end

  before do
    Dependabot::Experiments.register(:gradle_transitive_security_updates, true)
    stub_request(:get, "https://repo.maven.apache.org/maven2/org/example/child/maven-metadata.xml")
      .to_return(body: <<~XML)
        <metadata><groupId>org.example</groupId><artifactId>child</artifactId>
        <versioning><release>1.1</release><versions><version>1.0</version><version>1.1</version></versions>
        </versioning></metadata>
      XML
  end

  describe "dependency discovery" do
    it "discovers a lockfile-only dependency without treating it as a direct requirement" do
      expect(dependency.version).to eq("1.0")
      expect(dependency.requirements).to be_empty
      expect(dependency.top_level?).to be(false)
    end

    it "preserves declared dependencies" do
      direct = T.must(parser.parse.find { |dep| dep.name == "org.example:parent" })
      expect(direct.version).to eq("1.0")
      expect(direct.requirements.map(&:file)).to eq(["build.gradle"])
    end

    it "preserves existing discovery when the experiment is disabled" do
      Dependabot::Experiments.register(:gradle_transitive_security_updates, false)
      expect(parser.parse.map(&:name)).to eq(["org.example:parent"])
    end

    it "reports malformed lockfiles" do
      T.must(files.find { |file| file.name == "gradle.lockfile" }).content = "not a lockfile entry\n"
      expect { parser.parse }.to raise_error(Dependabot::DependencyFileNotParseable)
    end

    it "rejects dependency entries without configurations to verify" do
      T.must(files.find { |file| file.name == "gradle.lockfile" }).content = "org.example:child:1.0=\n"
      expect { parser.parse }.to raise_error(Dependabot::DependencyFileNotParseable, /Missing locked configurations/)
    end

    it "retains the lowest locked version across subprojects" do
      files << Dependabot::DependencyFile.new(
        name: "app/gradle.lockfile", content: "org.example:child:0.9=runtimeClasspath\n"
      )
      expect(dependency.version).to eq("0.9")
      expect(T.must(dependency.subdependency_metadata).length).to eq(2)
    end
  end

  describe "lockfile-only updates" do
    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
    end

    it "checks resolvability and returns an update without unlocking direct requirements" do
      expect(checker.can_update?(requirements_to_unlock: :none)).to be(true)
      updated = T.must(checker.updated_dependencies(requirements_to_unlock: :none).first)
      expect(updated.version).to eq("1.1")
      expect(updated.previous_version).to eq("1.0")
      expect(updated.requirements).to be_empty
      expect(updated.source_string("url")).to eq("https://repo.maven.apache.org/maven2")
      expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
        match(/\A(?!.*--(?:write|update)-locks).*dependabotResolveAll/), cwd: kind_of(String)
      ).once
    end

    it "returns only the changed lockfile through the file updater" do
      updated = checker.updated_dependencies(requirements_to_unlock: :none)
      updater = Dependabot::Gradle::FileUpdater.new(
        dependency_files: files, dependencies: updated, credentials: [], repo_contents_path: project_path
      )
      result = updater.updated_dependency_files
      expect(result.map(&:name)).to eq(["gradle.lockfile"])
      expect(T.must(result.first).content).to include("org.example:child:1.1=")
      expect(T.must(result.first).content).to include("org.example:parent:1.0=")
    end

    it "exposes every locked version to security jobs when the lowest version is safe" do
      files << Dependabot::DependencyFile.new(
        name: "app/gradle.lockfile", content: "org.example:child:0.9=runtimeClasspath\n"
      )
      expect(dependency.version).to eq("0.9")
      expect(dependency.all_versions).to contain_exactly("0.9", "1.0")
    end

    it "does not downgrade a higher locked version" do
      files << Dependabot::DependencyFile.new(
        name: "app/gradle.lockfile", content: "org.example:child:2.0=runtimeClasspath\n"
      )
      updater = Dependabot::Gradle::FileUpdater.new(
        dependency_files: files,
        dependencies: checker.updated_dependencies(requirements_to_unlock: :none),
        credentials: []
      )
      expect(updater.updated_dependency_files.map(&:name)).to eq(["gradle.lockfile"])
    end

    it "merges configurations when multiple locked versions become the same fixed version" do
      lockfile = T.must(files.find { |file| file.name == "gradle.lockfile" })
      lockfile.content = "org.example:child:0.9=compileClasspath\norg.example:child:1.0=runtimeClasspath\n"
      updater = Dependabot::Gradle::FileUpdater.new(
        dependency_files: files,
        dependencies: checker.updated_dependencies(requirements_to_unlock: :none),
        credentials: []
      )
      expect(T.must(updater.updated_dependency_files.first).content)
        .to eq("org.example:child:1.1=compileClasspath,runtimeClasspath\n")
    end

    it "applies transitive pins after regenerating lockfiles for direct updates" do
      direct = Dependabot::Dependency.new(
        name: "org.example:parent",
        version: "1.1",
        previous_version: "1.0",
        package_manager: "gradle",
        requirements: [{ file: "build.gradle", requirement: "1.1", groups: [], source: nil }],
        previous_requirements: [{ file: "build.gradle", requirement: "1.0", groups: [], source: nil }]
      )
      updated = checker.updated_dependencies(requirements_to_unlock: :none) + [direct]
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, cwd:|
        next unless command.include?("--write-locks")

        File.write(
          File.join(cwd, "gradle.lockfile"),
          "org.example:child:1.0=runtimeClasspath\norg.example:parent:1.1=runtimeClasspath\n"
        )
      end
      updater = Dependabot::Gradle::FileUpdater.new(
        dependency_files: files, dependencies: updated, credentials: [], repo_contents_path: project_path
      )
      result = updater.updated_dependency_files
      lockfile = T.must(result.find { |file| file.name == "gradle.lockfile" })
      expect(lockfile.content).to include("org.example:child:1.1=", "org.example:parent:1.1=")
    end

    it "uses registries declared by the locked subproject" do
      T.must(files.find { |file| file.name == "gradle.lockfile" }).name = "app/gradle.lockfile"
      files << Dependabot::DependencyFile.new(
        name: "app/build.gradle", content: "repositories { maven { url 'https://repo.example/maven' } }\n"
      )
      stub_request(:get, "https://repo.example/maven/org/example/child/maven-metadata.xml")
        .to_return(body: "<metadata><versioning><versions><version>1.1</version></versions></versioning></metadata>")
      expect(checker.lowest_security_fix_version&.to_s).to eq("1.1")
      expect(WebMock).to have_requested(:get, "https://repo.example/maven/org/example/child/maven-metadata.xml")
      stub_request(:get, "https://repo.example/maven/org/example/child/1.1/child-1.1.pom")
        .to_return(body: "<project><url>https://github.com/example/child</url></project>")
      updated = T.must(checker.updated_dependencies(requirements_to_unlock: :none).first)
      finder = Dependabot::Gradle::MetadataFinder.new(dependency: updated, credentials: [])
      expect(finder.source_url).to eq("https://github.com/example/child")
    end

    context "with a higher vulnerable version in another project" do
      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      let(:advisories) do
        [Dependabot::SecurityAdvisory.new(
          dependency_name: "org.example:child",
          package_manager: "gradle",
          vulnerable_versions: [Dependabot::Gradle::Requirement.new("< 1.2")]
        )]
      end

      it "selects a fix newer than every vulnerable locked version" do
        files << Dependabot::DependencyFile.new(
          name: "app/gradle.lockfile", content: "org.example:child:1.1=runtimeClasspath\n"
        )
        stub_request(:get, "https://repo.maven.apache.org/maven2/org/example/child/maven-metadata.xml")
          .to_return(body: <<~XML)
            <metadata><versioning><versions>
            <version>1.0</version><version>1.1</version><version>1.2</version>
            </versions></versioning></metadata>
          XML
        updated = T.must(checker.updated_dependencies(requirements_to_unlock: :none).first)
        expect(updated.previous_version).to eq("1.1")
        expect(updated.version).to eq("1.2")
      end
    end

    context "without a security advisory" do
      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      let(:advisories) { [] }

      it "does not introduce transitive version updates" do
        expect(checker.can_update?(requirements_to_unlock: :none)).to be(false)
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
      end
      # rubocop:enable RSpec/ScatteredLet
    end
  end

  describe "native Gradle verification" do
    it "creates a lockfile-only update that resolves without temporary overrides" do
      updated = checker.updated_dependencies(requirements_to_unlock: :none)
      expect(updated.map(&:version)).to eq(["1.1"])

      updater = Dependabot::Gradle::FileUpdater.new(
        dependency_files: files, dependencies: updated, credentials: [], repo_contents_path: project_path
      )
      result = updater.updated_dependency_files
      expect(result.map(&:name)).to eq(["gradle.lockfile"])
      expect(T.must(result.first).content).to include("org.example:child:1.1=")
    end

    it "reports a strict parent constraint as unresolvable" do
      allow(Dependabot.logger).to receive(:info)
      buildfile = T.must(files.find { |file| file.name == "build.gradle" })
      buildfile.content = T.must(buildfile.content) + <<~GRADLE

        dependencies {
            constraints {
                implementation('org.example:child') {
                    version { strictly '1.0' }
                }
            }
        }
      GRADLE
      expect(checker.can_update?(requirements_to_unlock: :none)).to be(false)
      expect(checker.updated_dependencies(requirements_to_unlock: :none)).to be_empty
      expect(Dependabot.logger).to have_received(:info).with(include("Cannot update transitive Gradle dependency"))
    end

    it "validates custom-mapped subprojects as well as the root project" do
      T.must(files.find { |file| file.name == "settings.gradle" }).content =
        "include(':service')\nproject(':service').projectDir = file('app')\n"
      files << Dependabot::DependencyFile.new(
        name: "app/build.gradle",
        content: File.read(File.join(project_path, "build.gradle")).sub("uri('repository')", "uri('../repository')")
      )
      files << Dependabot::DependencyFile.new(
        name: "app/gradle.lockfile", content: File.read(File.join(project_path, "gradle.lockfile"))
      )
      expect(checker.can_update?(requirements_to_unlock: :none)).to be(true)
    end

    it "validates included builds independently without applying expectations to unrelated builds" do
      T.must(files.find { |file| file.name == "settings.gradle" }).content =
        "includeBuild('tools')\nincludeBuild('unrelated')\n"
      files << Dependabot::DependencyFile.new(name: "tools/settings.gradle", content: "rootProject.name = 'tools'\n")
      files << Dependabot::DependencyFile.new(
        name: "tools/build.gradle",
        content: File.read(File.join(project_path, "build.gradle")).sub("uri('repository')", "uri('../repository')")
      )
      files << Dependabot::DependencyFile.new(
        name: "tools/gradle.lockfile", content: File.read(File.join(project_path, "gradle.lockfile"))
      )
      files << Dependabot::DependencyFile.new(
        name: "unrelated/settings.gradle", content: "rootProject.name = 'unrelated'\n"
      )
      files << Dependabot::DependencyFile.new(name: "unrelated/build.gradle", content: "plugins { id 'java' }\n")
      updated = Dependabot::Dependency.new(
        name: dependency.name,
        version: "1.1",
        previous_version: "1.0",
        requirements: [],
        previous_requirements: [],
        package_manager: "gradle"
      )
      updater = Dependabot::Gradle::FileUpdater.new(
        dependency_files: files, dependencies: [updated], credentials: [], repo_contents_path: project_path
      )
      expect(updater.updated_dependency_files.map(&:name)).to contain_exactly(
        "gradle.lockfile",
        "tools/gradle.lockfile"
      )
    end
  end
end
