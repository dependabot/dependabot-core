# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/source"
require "dependabot/gradle/file_fetcher"
require "dependabot/gradle/file_parser"
require "dependabot/gradle/file_updater"

# The fixture builds resolve from spec/fixtures/maven_repo, which lies outside the checkout like a remote repository.
RSpec.describe Dependabot::Gradle::FileUpdater do
  subject(:updated_files) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: [dependency],
      credentials: [],
      repo_contents_path: repo_contents_path
    ).updated_dependency_files
  end

  let(:repo_contents_path) { build_tmp_repo("lockfiles") }
  let(:directory) { "/" }
  let(:source) { Dependabot::Source.new(provider: "github", repo: "example/lockfiles", directory: directory) }
  let(:dependency_files) do
    Dependabot::Gradle::FileFetcher.new(source: source, credentials: [], repo_contents_path: repo_contents_path).files
  end
  let(:dependency) { bump("com.example:alpha", to: "1.1") }
  let(:bumped_entries) do
    [
      "com.example:alpha:1.1=compileClasspath,runtimeClasspath,testCompileClasspath,testRuntimeClasspath",
      "com.example:beta:1.0=compileClasspath,runtimeClasspath,testCompileClasspath,testRuntimeClasspath",
      "empty=annotationProcessor,testAnnotationProcessor"
    ]
  end

  before do
    ENV["TEST_MAVEN_REPO"] = File.expand_path("spec/fixtures/maven_repo")
  end

  after do
    ENV.delete("TEST_MAVEN_REPO")
    FileUtils.rm_rf(repo_contents_path)
  end

  def bump(name, to:)
    current = Dependabot::Gradle::FileParser.new(dependency_files: dependency_files, source: source)
                                            .parse.find { |dependency| dependency.name == name }
    Dependabot::Dependency.new(
      name: name,
      version: to,
      previous_version: current.version,
      requirements: current.requirements.map { |requirement| requirement.merge(requirement: to) },
      previous_requirements: current.requirements,
      package_manager: "gradle"
    )
  end

  def lock_entries(name)
    updated_files.find { |file| file.name == name }&.content&.lines(chomp: true)&.grep_v(/\A#/)
  end

  def expect_gradle_to_accept_locks
    updated_files.each { |file| File.write(File.join(repo_contents_path, file.path), file.content) }
    script = File.join(repo_contents_path, "verify-locks.gradle")
    # Resolving without --write-locks fails when the lock state does not match what the build resolves.
    File.write(script, <<~GRADLE)
      gradle.projectsEvaluated {
        gradle.rootProject.allprojects { project ->
          project.configurations.matching { it.canBeResolved }.toList().each { it.resolve() }
        }
      }
    GRADLE
    Dependabot::SharedHelpers.run_shell_command(
      "gradle --offline --no-daemon --init-script #{script} help",
      cwd: File.join(repo_contents_path, directory)
    )
  end

  context "with a single-project build at the repository root" do
    it "rewrites the lockfile" do
      expect(lock_entries("gradle.lockfile")).to eq(bumped_entries)
      expect_gradle_to_accept_locks
    end
  end

  context "with a multi-project build" do
    let(:directory) { "/multi_project" }

    it "rewrites the subproject lockfiles" do
      expect(lock_entries("app/gradle.lockfile")).to eq(bumped_entries)
      expect(lock_entries("lib/gradle.lockfile")).to eq(bumped_entries)
      expect_gradle_to_accept_locks
    end
  end

  context "when a locked configuration cannot be resolved" do
    let(:directory) { "/unresolvable_configuration" }

    it "rewrites the other configurations and keeps the failed one's entries" do
      expect(lock_entries("gradle.lockfile")).to eq(
        [
          "com.example:alpha:1.0=testRuntimeClasspath",
          "com.example:alpha:1.1=compileClasspath,runtimeClasspath,testCompileClasspath",
          "com.example:beta:1.0=compileClasspath,runtimeClasspath,testCompileClasspath",
          "empty=annotationProcessor,testAnnotationProcessor"
        ]
      )
    end
  end

  context "when a locked configuration only gets its dependencies while it resolves" do
    let(:directory) { "/lazy_configuration" }
    let(:dependency) { bump("com.example:tool", to: "1.1") }

    it "rewrites that configuration" do
      expect(lock_entries("gradle.lockfile")).to eq(["com.example:tool:1.1=tool", "empty="])
      expect_gradle_to_accept_locks
    end
  end

  context "when the project applies a convention plugin from buildSrc" do
    let(:directory) { "/build_src" }

    it "builds the plugin and rewrites the lockfile" do
      expect(lock_entries("gradle.lockfile")).to eq(bumped_entries)
      expect_gradle_to_accept_locks
    end
  end

  context "when the project applies a convention plugin from a nested project of an included build" do
    let(:directory) { "/included_build_plugin" }

    it "builds the plugin and rewrites the lockfile" do
      expect(lock_entries("app/gradle.lockfile")).to eq(bumped_entries)
      expect_gradle_to_accept_locks
    end
  end

  context "with a composite build whose included build locks its own dependencies" do
    let(:directory) { "/composite" }

    it "rewrites the lockfiles of both builds" do
      expect(lock_entries("gradle.lockfile")).to eq(bumped_entries)
      expect(lock_entries("shared/gradle.lockfile")).to eq(bumped_entries)
      expect_gradle_to_accept_locks
    end
  end

  context "when a subproject is only included under a condition the build does not meet" do
    let(:directory) { "/conditional_include" }

    it "rewrites the lockfiles of the projects Gradle includes" do
      expect(updated_files.map(&:name)).to include("extra/build.gradle")
      expect(lock_entries("app/gradle.lockfile")).to eq(bumped_entries)
      expect_gradle_to_accept_locks
    end
  end

  context "when the lockfile does not record a locked configuration yet" do
    let(:directory) { "/unrecorded_configuration" }

    it "rewrites the recorded configurations and records the newly locked one" do
      expect(lock_entries("gradle.lockfile")).to eq(bumped_entries)
      expect_gradle_to_accept_locks
    end
  end
end
