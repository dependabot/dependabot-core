# typed: strict
# frozen_string_literal: true

require "json"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/swift/file_updater/xcproj_updater"

RSpec.describe Dependabot::Swift::FileUpdater::XcprojUpdater do
  extend T::Sig

  sig { returns(String) }
  subject(:updated_content) do
    described_class.new(xcproj_file: xcproj_file, dependencies: dependencies).updated_xcproj_content
  end

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::DependencyFile) }
  let(:xcproj_file) do
    Dependabot::DependencyFile.new(
      name: "MyApp.xcodeproj/project.xcproj",
      content: xcproj_content,
      support_file: true
    )
  end

  sig { returns(T.nilable(String)) }
  let(:xcproj_content) do
    fixture("projects", "xcode_project_xcproj_multi_req", "MyApp.xcodeproj", "project.xcproj")
  end

  sig { returns(T::Array[Dependabot::Dependency]) }
  let(:dependencies) { [] }
  # rubocop:enable RSpec/ScatteredLet

  sig { params(name: String, version: String).returns(Dependabot::Dependency) }
  def dependency(name, version)
    Dependabot::Dependency.new(
      name: name,
      version: version,
      requirements: [],
      package_manager: "swift"
    )
  end

  sig { params(content: String, repository: String).returns(Object) }
  def version_constraint(content, repository)
    package = JSON.parse(content, allow_trailing_comma: true)["packages"].find do |pkg|
      pkg["repository"] == repository
    end
    package["version"]
  end

  sig { params(before: String, after: String).returns(T::Array[[String, T.nilable(String)]]) }
  def changed_lines(before, after)
    before.lines.zip(after.lines).reject { |a, b| a == b }
  end

  describe "#updated_xcproj_content" do
    context "with an up-to-next-major-version requirement" do
      sig { returns(T::Array[Dependabot::Dependency]) }
      let(:dependencies) { [dependency("github.com/apple/swift-nio", "2.60.0")] }

      it "raises the lower bound" do
        expect(version_constraint(updated_content, "https://github.com/apple/swift-nio.git"))
          .to eq("up-to-next-major-version" => "2.60.0")
      end

      it "changes only that version string" do
        expect(changed_lines(T.must(xcproj_content), updated_content)).to eq(
          [[
            "        \"up-to-next-major-version\": \"2.54.0\",\n",
            "        \"up-to-next-major-version\": \"2.60.0\",\n"
          ]]
        )
      end
    end

    context "with an up-to-next-minor-version requirement" do
      sig { returns(T::Array[Dependabot::Dependency]) }
      let(:dependencies) { [dependency("github.com/apple/swift-collections", "1.0.5")] }

      it "raises the lower bound" do
        expect(version_constraint(updated_content, "https://github.com/apple/swift-collections.git"))
          .to eq("up-to-next-minor-version" => "1.0.5")
      end
    end

    context "with an exact version requirement" do
      sig { returns(T::Array[Dependabot::Dependency]) }
      let(:dependencies) { [dependency("github.com/apple/swift-argument-parser", "1.3.0")] }

      it "replaces the version" do
        expect(version_constraint(updated_content, "https://github.com/apple/swift-argument-parser"))
          .to eq("version" => "1.3.0")
      end

      it "does not touch other packages" do
        expect(changed_lines(T.must(xcproj_content), updated_content).length).to eq(1)
      end
    end

    context "with a version-range requirement" do
      sig { returns(T::Array[Dependabot::Dependency]) }
      let(:dependencies) { [dependency("github.com/apple/swift-log", "1.5.0")] }

      it "raises the lower bound and keeps the upper bound" do
        expect(version_constraint(updated_content, "https://github.com/apple/swift-log.git"))
          .to eq("version-range" => "1.5.0..<2.0.0")
      end
    end

    context "with a version-range-min and version-range-max requirement" do
      context "when the new lower bound is a plain version" do
        sig { returns(T::Array[Dependabot::Dependency]) }
        let(:dependencies) { [dependency("github.com/swiftlang/swift-syntax", "600.0.1")] }

        it "writes the canonical version-range form" do
          expect(version_constraint(updated_content, "https://github.com/swiftlang/swift-syntax.git"))
            .to eq("version-range" => "600.0.1..<601.0.0")
          expect(updated_content).to include("        \"version-range\": \"600.0.1..<601.0.0\",\n      },")
        end
      end

      context "when the new lower bound is a prerelease" do
        sig { returns(T::Array[Dependabot::Dependency]) }
        let(:dependencies) { [dependency("github.com/swiftlang/swift-syntax", "600.0.0-prerelease-2024-07-24")] }

        it "keeps the min and max pair" do
          expect(version_constraint(updated_content, "https://github.com/swiftlang/swift-syntax.git")).to eq(
            "version-range-min" => "600.0.0-prerelease-2024-07-24",
            "version-range-max" => "601.0.0"
          )
        end
      end
    end

    context "with branch and revision requirements" do
      sig { returns(T::Array[Dependabot::Dependency]) }
      let(:dependencies) do
        [
          dependency("github.com/apple/swift-algorithms", "1.2.0"),
          dependency("github.com/apple/swift-numerics", "1.0.2")
        ]
      end

      it "leaves the file unchanged" do
        expect(updated_content).to eq(xcproj_content)
      end
    end

    context "with a dependency that is not in the project" do
      sig { returns(T::Array[Dependabot::Dependency]) }
      let(:dependencies) { [dependency("github.com/apple/swift-crypto", "3.0.0")] }

      it "leaves the file unchanged" do
        expect(updated_content).to eq(xcproj_content)
      end
    end

    context "with a repository written as an SCP-style URL" do
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(T.nilable(String)) }
      let(:xcproj_content) do
        <<~JSON
          {
            "packages": [
              {
                "kind": "remote",
                "repository": "git@github.com:apple/swift-nio.git",
                "version": {
                  "up-to-next-major-version": "2.54.0",
                },
              },
            ],
          }
        JSON
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      let(:dependencies) { [dependency("github.com/apple/swift-nio", "2.60.0")] }
      # rubocop:enable RSpec/ScatteredLet

      it "matches the dependency" do
        expect(updated_content).to include("\"up-to-next-major-version\": \"2.60.0\"")
      end
    end

    context "with the version constraint written before the repository" do
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(T.nilable(String)) }
      let(:xcproj_content) do
        <<~JSON
          {
            "packages": [
              {
                "version": {
                  "version": "1.2.0",
                },
                "kind": "remote",
                "repository": "https://github.com/apple/swift-argument-parser",
              }, {
                "kind": "remote",
                "repository": "https://github.com/apple/swift-nio.git",
                "version": {
                  "up-to-next-major-version": "2.54.0",
                },
              },
            ],
          }
        JSON
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      let(:dependencies) { [dependency("github.com/apple/swift-argument-parser", "1.8.2")] }
      # rubocop:enable RSpec/ScatteredLet

      it "replaces the version and changes nothing else" do
        expect(changed_lines(T.must(xcproj_content), updated_content)).to eq(
          [["        \"version\": \"1.2.0\",\n", "        \"version\": \"1.8.2\",\n"]]
        )
      end
    end

    context "without content" do
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(T.nilable(String)) }
      let(:xcproj_content) { nil }

      sig { returns(T::Array[Dependabot::Dependency]) }
      let(:dependencies) { [dependency("github.com/apple/swift-nio", "2.60.0")] }
      # rubocop:enable RSpec/ScatteredLet

      it "raises a DependencyFileNotParseable error" do
        expect { updated_content }.to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end
  end
end
