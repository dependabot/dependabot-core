# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/swift"

RSpec.describe Dependabot::Swift::DependencyGrapher do
  subject(:grapher) do
    Dependabot::DependencyGraphers.for_package_manager("swift").new(
      file_parser: parser
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "mona/Example",
      directory: "/"
    )
  end

  context "with a classic SPM project" do
    let(:project_name) { "Example" }
    let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

    let(:parser) do
      Dependabot::FileParsers.for_package_manager("swift").new(
        dependency_files: files,
        source: source,
        repo_contents_path: repo_contents_path
      )
    end

    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "Package.swift",
          content: fixture("projects", project_name, "Package.swift")
        ),
        Dependabot::DependencyFile.new(
          name: "Package.resolved",
          content: fixture("projects", project_name, "Package.resolved")
        )
      ]
    end

    describe "#relevant_dependency_file" do
      it "returns Package.resolved when present" do
        resolved = files.find { |f| f.name == "Package.resolved" }
        expect(grapher.relevant_dependency_file).to eq(resolved)
      end
    end

    describe "#resolved_dependencies" do
      it "returns correctly structured ResolvedDependency objects" do
        resolved = grapher.resolved_dependencies

        expect(resolved).not_to be_empty

        # Check a direct dependency
        reactive_purl = "pkg:swift/github.com/reactivecocoa/reactiveswift@7.1.0"
        reactive = resolved[reactive_purl]
        expect(reactive).not_to be_nil
        expect(reactive.package_url).to eq(reactive_purl)
        expect(reactive.direct).to be(true)
        expect(reactive.runtime).to be(true)
        expect(reactive.dependencies).to eq([])
      end

      it "marks indirect dependencies correctly" do
        resolved = grapher.resolved_dependencies

        # xctest-dynamic-overlay is a subdependency (no requirements in Package.swift)
        xctest_purl = "pkg:swift/github.com/pointfreeco/xctest-dynamic-overlay@0.8.5"
        xctest = resolved[xctest_purl]
        expect(xctest).not_to be_nil
        expect(xctest.direct).to be(false)
        expect(xctest.runtime).to be(true)
      end

      it "generates valid PURLs for all dependencies" do
        resolved = grapher.resolved_dependencies

        resolved.each do |purl, dep|
          expect(purl).to start_with("pkg:swift/")
          expect(dep.package_url).to eq(purl)
        end
      end

      describe "subdependency relationships" do
        it "assigns child dependencies from the dependency tree" do
          resolved = grapher.resolved_dependencies

          # combine-schedulers depends on xctest-dynamic-overlay
          combine_purl = "pkg:swift/github.com/pointfreeco/combine-schedulers@0.10.0"
          combine = resolved[combine_purl]
          expect(combine).not_to be_nil
          expect(combine.dependencies).to include(
            "pkg:swift/github.com/pointfreeco/xctest-dynamic-overlay@0.8.5"
          )
        end

        it "returns empty dependencies for leaf packages" do
          resolved = grapher.resolved_dependencies

          # reactiveswift is a leaf dependency (no children in the tree that are also resolved)
          reactive_purl = "pkg:swift/github.com/reactivecocoa/reactiveswift@7.1.0"
          reactive = resolved[reactive_purl]
          expect(reactive).not_to be_nil
          expect(reactive.dependencies).to eq([])
        end
      end

      describe "when fetching package relationships fails" do
        let(:swift_command_error) { StandardError.new("swift command failed") }

        before do
          # Let prepare! run normally so dependencies are parsed, then
          # break the grapher's tree-fetching by making the JSON parse invalid
          grapher.send(:prepare!)
          allow(JSON).to receive(:parse).and_raise(swift_command_error)
        end

        it "sets the error flag without raising" do
          grapher.resolved_dependencies

          expect(grapher.errored_fetching_subdependencies).to be(true)
        end

        it "assigns the original error to the grapher" do
          grapher.resolved_dependencies

          expect(grapher.subdependency_error).to eql(swift_command_error)
        end

        it "returns empty dependencies for all resolved packages" do
          depends_on_values = grapher.resolved_dependencies.map { |_, dep| dep.dependencies }

          expect(depends_on_values).to all(be_empty)
        end
      end
    end
  end

  context "with a classic SPM project without Package.resolved" do
    let(:project_name) { "manifest-only" }
    let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

    let(:parser) do
      Dependabot::FileParsers.for_package_manager("swift").new(
        dependency_files: files,
        source: source,
        repo_contents_path: repo_contents_path
      )
    end

    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "Package.swift",
          content: fixture("projects", project_name, "Package.swift")
        )
      ]
    end

    describe "#relevant_dependency_file" do
      it "falls back to Package.swift" do
        manifest = files.find { |f| f.name == "Package.swift" }
        expect(grapher.relevant_dependency_file).to eq(manifest)
      end
    end

    describe "#resolved_dependencies" do
      it "resolves dependencies including transitive ones" do
        resolved = grapher.resolved_dependencies

        expect(resolved).not_to be_empty

        # swift-nio-http2 is declared in Package.swift
        nio_http2_deps = resolved.select { |purl, _| purl.include?("swift-nio-http2") }
        expect(nio_http2_deps).not_to be_empty

        # Transitive dependencies should also be present
        expect(resolved.size).to be > 1
      end

      it "includes subdependency relationships" do
        resolved = grapher.resolved_dependencies

        has_subdeps = resolved.values.any? { |dep| dep.dependencies.any? }
        expect(has_subdeps).to be(true)
      end

      it "emits a missing lockfile warning" do
        expect(Dependabot.logger).to receive(:warn).with(/No Package\.resolved was found/)

        grapher.resolved_dependencies
      end
    end
  end

  context "with an Xcode SPM project" do
    let(:project_name) { "xcode_project" }
    let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

    let(:parser) do
      Dependabot::FileParsers.for_package_manager("swift").new(
        dependency_files: files,
        source: source,
        repo_contents_path: repo_contents_path
      )
    end

    let(:resolved_path) { "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" }

    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.pbxproj",
          content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
          support_file: true
        ),
        Dependabot::DependencyFile.new(
          name: resolved_path,
          content: fixture(
            "projects",
            project_name,
            "MyApp.xcodeproj",
            "project.xcworkspace",
            "xcshareddata",
            "swiftpm",
            "Package.resolved"
          )
        )
      ]
    end

    describe "#relevant_dependency_file" do
      it "returns the Xcode Package.resolved" do
        resolved = files.find { |f| f.name == resolved_path }
        expect(grapher.relevant_dependency_file).to eq(resolved)
      end
    end

    describe "#resolved_dependencies" do
      it "returns correctly structured ResolvedDependency objects" do
        resolved = grapher.resolved_dependencies

        expect(resolved).not_to be_empty

        nio_purl = "pkg:swift/github.com/apple/swift-nio@2.54.0"
        nio = resolved[nio_purl]
        expect(nio).not_to be_nil
        expect(nio.package_url).to eq(nio_purl)
        expect(nio.direct).to be(true)
        expect(nio.runtime).to be(true)
        expect(nio.dependencies).to eq([])
      end
    end
  end

  context "with both Package.swift and Xcode project present" do
    let(:project_name) { "xcode_project_with_manifest" }
    let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

    let(:parser) do
      Dependabot::FileParsers.for_package_manager("swift").new(
        dependency_files: files,
        source: source,
        repo_contents_path: repo_contents_path
      )
    end

    let(:files) do
      [
        Dependabot::DependencyFile.new(
          name: "Package.swift",
          content: fixture("projects", project_name, "Package.swift")
        ),
        Dependabot::DependencyFile.new(
          name: "Package.resolved",
          content: fixture("projects", project_name, "Package.resolved")
        ),
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.pbxproj",
          content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
          support_file: true
        ),
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
          content: fixture(
            "projects",
            project_name,
            "MyApp.xcodeproj",
            "project.xcworkspace",
            "xcshareddata",
            "swiftpm",
            "Package.resolved"
          )
        )
      ]
    end

    describe "#relevant_dependency_file" do
      it "prefers classic SPM (Package.resolved) over Xcode Package.resolved" do
        resolved = files.find { |f| f.name == "Package.resolved" }
        expect(grapher.relevant_dependency_file).to eq(resolved)
      end
    end
  end

  context "when no dependency files are present" do
    let(:parser) do
      instance_double(
        Dependabot::Swift::FileParser,
        dependency_files: [],
        parse: [],
        credentials: []
      )
    end

    describe "#relevant_dependency_file" do
      it "raises a DependabotError" do
        expect { grapher.relevant_dependency_file }.to raise_error(Dependabot::DependabotError)
      end
    end
  end
end
