# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser/lockfile_parser"

RSpec.describe Dependabot::NpmAndYarn::FileParser::LockfileParser do
  subject(:lockfile_parser) do
    described_class.new(
      dependency_files: dependency_files
    )
  end
  let(:npm_lockfile) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: npm_lockfile_content
    )
  end
  let(:npm_lockfile_content) do
    fixture("npm_lockfiles", npm_lockfile_fixture_name)
  end
  let(:npm_lockfile_fixture_name) { "only_dev_dependencies.json" }
  let(:yarn_lockfile) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: yarn_lockfile_content
    )
  end
  let(:yarn_lockfile_content) do
    fixture("yarn_lockfiles", yarn_lockfile_fixture_name)
  end
  let(:yarn_lockfile_fixture_name) { "only_dev_dependencies.lock" }
  let(:npm_shrinkwrap) do
    Dependabot::DependencyFile.new(
      name: "npm-shrinkwrap.json",
      content: npm_shrinkwrap_content
    )
  end
  let(:npm_shrinkwrap_content) do
    fixture("npm_lockfiles", npm_shrinkwrap_fixture_name)
  end
  let(:npm_shrinkwrap_fixture_name) { "only_dev_dependencies.json" }

  describe "#parse" do
    subject(:dependencies) { lockfile_parser.parse }

    context "for yarn lockfiles" do
      let(:dependency_files) { [yarn_lockfile] }

      it "parses the dependencies" do
        expect(dependencies.map(&:name)).to contain_exactly("etag")
      end

      context "that contains an empty version string" do
        let(:yarn_lockfile_fixture_name) { "empty_version.lock" }
        # Lockfile contains 10 dependencies but one has an empty version
        its(:length) { is_expected.to eq(9) }
      end

      context "that contain multiple dependencies" do
        let(:yarn_lockfile_fixture_name) { "no_lockfile_change.lock" }

        its(:length) { is_expected.to eq(393) }

        describe "a repeated dependency" do
          subject { dependencies.find { |d| d.name == "acorn" } }

          its(:version) { is_expected.to eq("5.1.1") }
        end
      end

      context "that contain bad lockfile" do
        let(:yarn_lockfile_content) do
          "{ something: else }"
        end

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }.
            to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("yarn.lock")
            end
        end
      end
    end

    context "for npm lockfiles" do
      let(:dependency_files) { [npm_lockfile] }

      it "parses the dependencies" do
        expect(dependencies.map(&:name)).to contain_exactly("etag")
      end

      context "that contain multiple dependencies" do
        let(:npm_lockfile_fixture_name) { "blank_requirement.json" }

        its(:length) { is_expected.to eq(23) }

        describe "a repeated dependency" do
          subject { dependencies.find { |d| d.name == "lodash" } }

          its(:version) { is_expected.to eq("2.4.1") }
        end
      end

      context "that contains an empty version string" do
        let(:npm_lockfile_fixture_name) { "empty_version.json" }
        # Lockfile contains 10 dependencies but one has an empty version
        its(:length) { is_expected.to eq(9) }
      end

      context "that has URL versions (i.e., is from a bad version of npm)" do
        let(:npm_lockfile_fixture_name) { "url_versions.json" }
        # All but 1 dependency in the lockfile has a URL version
        its(:length) { is_expected.to eq(1) }
      end

      context "that contain bad json" do
        let(:npm_lockfile_content) do
          '{ "bad": "json" "no": "comma" }'
        end

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }.
            to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("package-lock.json")
            end
        end
      end
    end

    context "for npm shrinkwraps" do
      let(:dependency_files) { [npm_shrinkwrap] }

      it "parses the dependencies" do
        expect(dependencies.map(&:name)).to contain_exactly("etag")
      end

      context "that contain multiple dependencies" do
        let(:npm_shrinkwrap_fixture_name) { "blank_requirement.json" }

        its(:length) { is_expected.to eq(23) }

        describe "a repeated dependency" do
          subject { dependencies.find { |d| d.name == "lodash" } }

          its(:version) { is_expected.to eq("2.4.1") }
        end
      end

      context "that contains an empty version string" do
        let(:npm_shrinkwrap_fixture_name) { "empty_version.json" }
        # Lockfile contains 10 dependencies but one has an empty version
        its(:length) { is_expected.to eq(9) }
      end

      context "that contain bad json" do
        let(:npm_shrinkwrap_content) do
          '{ "bad": "json" "no": "comma" }'
        end

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }.
            to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("npm-shrinkwrap.json")
            end
        end
      end
    end
  end

  describe "#lockfile_details" do
    subject(:lockfile_details) do
      lockfile_parser.lockfile_details(
        dependency_name: dependency_name,
        requirement: requirement,
        manifest_name: manifest_name
      )
    end
    let(:dependency_name) { "etag" }
    let(:requirement) { nil }
    let(:manifest_name) { "package.json" }

    context "for yarn lockfiles" do
      let(:dependency_files) { [yarn_lockfile] }

      it "finds the dependency" do
        expect(lockfile_details).to eq(
          "resolved" => "https://registry.yarnpkg.com/etag/-/etag-1.8.0.tgz"\
                        "#6f631aef336d6c46362b51764044ce216be3c051",
          "version" => "1.8.0"
        )
      end

      context "that contain duplicate dependencies" do
        let(:yarn_lockfile_fixture_name) { "no_lockfile_change.lock" }
        let(:dependency_name) { "ansi-styles" }
        let(:requirement) { "^2.2.1" }

        it "finds the one matching the requirement" do
          expect(lockfile_details).to eq(
            "version" => "2.2.1",
            "resolved" => "https://registry.yarnpkg.com/ansi-styles/-/"\
                           "ansi-styles-2.2.1.tgz#"\
                           "b432dd3358b634cf75e1e4664368240533c1ddbe"
          )
        end

        context "when the requiremtn doesn't match" do
          let(:requirement) { "^3.3.0" }

          it { is_expected.to eq(nil) }
        end
      end
    end

    context "for npm lockfiles" do
      let(:dependency_files) { [npm_lockfile] }

      it "finds the dependency" do
        expect(lockfile_details).to eq(
          "version" => "1.8.1",
          "resolved" => "https://registry.npmjs.org/etag/-/etag-1.8.1.tgz",
          "integrity" => "sha1-Qa4u62XvpiJorr/qg6x9eSmbCIc=",
          "dev" => true
        )
      end

      context "when a nested lockfile is also present" do
        let(:dependency_files) { [npm_lockfile, irrelevant_npm_lockfile] }
        let(:irrelevant_npm_lockfile) do
          Dependabot::DependencyFile.new(
            name: "nested/package-lock.json",
            content: fixture("npm_lockfiles", "package1.json")
          )
        end

        it "finds the correct dependency" do
          expect(lockfile_details).to eq(
            "version" => "1.8.1",
            "resolved" => "https://registry.npmjs.org/etag/-/etag-1.8.1.tgz",
            "integrity" => "sha1-Qa4u62XvpiJorr/qg6x9eSmbCIc=",
            "dev" => true
          )
        end

        context "that should be used for this manifest" do
          let(:manifest_name) { "nested/package.json" }

          it "finds the correct dependency" do
            expect(lockfile_details).to eq(
              "version" => "1.8.0",
              "resolved" => "https://registry.npmjs.org/etag/-/etag-1.8.0.tgz",
              "integrity" => "sha1-Qa4u62XvpiJorr/qg6x9eSm111c="
            )
          end
        end
      end
    end

    context "for npm shrinkwraps" do
      let(:dependency_files) { [npm_shrinkwrap] }

      it "finds the dependency" do
        expect(lockfile_details).to eq(
          "version" => "1.8.1",
          "resolved" => "https://registry.npmjs.org/etag/-/etag-1.8.1.tgz",
          "integrity" => "sha1-Qa4u62XvpiJorr/qg6x9eSmbCIc=",
          "dev" => true
        )
      end
    end
  end
end
