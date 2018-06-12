# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/elixir/hex"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Elixir::Hex do
  it_behaves_like "a dependency file parser"

  let(:files) { [mixfile, lockfile] }
  let(:mixfile) do
    Dependabot::DependencyFile.new(
      name: "mix.exs",
      content: fixture("elixir", "mixfiles", mixfile_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "mix.lock",
      content: fixture("elixir", "lockfiles", lockfile_fixture_name)
    )
  end
  let(:mixfile_fixture_name) { "minor_version" }
  let(:lockfile_fixture_name) { "minor_version" }
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "with a ~> version specified" do
      its(:length) { is_expected.to eq(2) }

      describe "the last dependency" do
        subject(:dependency) { dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("plug")
          expect(dependency.version).to eq("1.3.5")
          expect(dependency.requirements).to eq(
            [{
              requirement: "~> 1.3.0",
              file: "mix.exs",
              groups: [],
              source: nil
            }]
          )
        end
      end
    end

    context "with an exact version specified" do
      let(:mixfile_fixture_name) { "exact_version" }
      let(:lockfile_fixture_name) { "exact_version" }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.production?).to eq(true)
          expect(dependency.name).to eq("phoenix")
          expect(dependency.version).to eq("1.2.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "== 1.2.1",
              file: "mix.exs",
              groups: [],
              source: nil
            }]
          )
        end
      end

      describe "the second dependency" do
        subject(:dependency) { dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("plug")
          expect(dependency.version).to eq("1.3.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.3.0",
              file: "mix.exs",
              groups: [],
              source: nil
            }]
          )
        end
      end
    end

    context "with no requirements specified" do
      let(:mixfile_fixture_name) { "no_requirement" }
      let(:lockfile_fixture_name) { "no_requirement" }

      describe "the last dependency" do
        subject(:dependency) { dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("plug")
          expect(dependency.version).to eq("1.3.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: nil,
              file: "mix.exs",
              groups: ["docs"],
              source: nil
            }]
          )
        end
      end
    end

    context "with a regex requirement specified" do
      let(:mixfile_fixture_name) { "regex_version" }
      let(:lockfile_fixture_name) { "regex_version" }

      describe "the last dependency" do
        subject(:dependency) { dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("wsecli")
          expect(dependency.version).
            to eq("a89054cf71c5ee9e780998e5acb2a78fd3419dd9")
          expect(dependency.requirements).to eq(
            [{
              requirement: nil,
              file: "mix.exs",
              groups: ["test"],
              source: {
                type: "git",
                url: "https://github.com/esl/wsecli.git",
                branch: "master",
                ref: nil
              }
            }]
          )
        end
      end
    end

    context "with a development dependency" do
      let(:mixfile_fixture_name) { "development_dependency" }
      let(:lockfile_fixture_name) { "development_dependency" }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.production?).to eq(false)
          expect(dependency.name).to eq("phoenix")
          expect(dependency.version).to eq("1.2.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "== 1.2.1",
              file: "mix.exs",
              groups: ["dev"],
              source: nil
            }]
          )
        end
      end

      describe "the second dependency" do
        subject(:dependency) { dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("plug")
          expect(dependency.version).to eq("1.3.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.3.0",
              file: "mix.exs",
              groups: %w(dev test),
              source: nil
            }]
          )
        end
      end
    end

    context "with a git source" do
      let(:mixfile_fixture_name) { "git_source" }
      let(:lockfile_fixture_name) { "git_source" }

      it "includes the git dependency" do
        expect(dependencies.length).to eq(2)
        expect(dependencies).to include(
          Dependabot::Dependency.new(
            name: "phoenix",
            version: "178ce1a2344515e9145599970313fcc190d4b881",
            requirements: [{
              requirement: nil,
              file: "mix.exs",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/phoenixframework/phoenix.git",
                branch: "master",
                ref: "v1.2.0"
              }
            }],
            package_manager: "hex"
          )
        )
      end

      context "with a tag (rather than a ref)" do
        let(:mixfile_fixture_name) { "git_source_with_charlist" }
        let(:lockfile_fixture_name) { "git_source_with_charlist" }

        it "includes the git dependency" do
          expect(dependencies.length).to eq(2)
          expect(dependencies).to include(
            Dependabot::Dependency.new(
              name: "phoenix",
              version: "178ce1a2344515e9145599970313fcc190d4b881",
              requirements: [{
                requirement: nil,
                file: "mix.exs",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/phoenixframework/phoenix.git",
                  branch: "master",
                  ref: "v1.2.0"
                }
              }],
              package_manager: "hex"
            )
          )
        end
      end
    end

    context "with an old elixir version" do
      let(:mixfile_fixture_name) { "old_elixir" }
      let(:lockfile_fixture_name) { "old_elixir" }

      its(:length) { is_expected.to eq(2) }
    end

    context "with a really old elixir version" do
      let(:mixfile_fixture_name) { "really_old_elixir" }
      let(:lockfile_fixture_name) { "really_old_elixir" }

      its(:length) { is_expected.to eq(7) }
    end

    context "with a call to read a version file" do
      let(:mixfile_fixture_name) { "loads_file" }
      let(:lockfile_fixture_name) { "exact_version" }

      its(:length) { is_expected.to eq(2) }
    end

    context "with a bad specification" do
      let(:mixfile_fixture_name) { "bad_spec" }
      let(:lockfile_fixture_name) { "exact_version" }

      its(:length) { is_expected.to eq(2) }
    end

    context "with an umbrella app" do
      let(:mixfile_fixture_name) { "umbrella" }
      let(:lockfile_fixture_name) { "umbrella" }
      let(:files) { [mixfile, lockfile, sub_mixfile1, sub_mixfile2] }
      let(:sub_mixfile1) do
        Dependabot::DependencyFile.new(
          name: "apps/dependabot_business/mix.exs",
          content: fixture("elixir", "mixfiles", "dependabot_business")
        )
      end
      let(:sub_mixfile2) do
        Dependabot::DependencyFile.new(
          name: "apps/dependabot_web/mix.exs",
          content: fixture("elixir", "mixfiles", "dependabot_web")
        )
      end

      it "parses the dependencies correctly" do
        expect(dependencies.length).to eq(3)
        expect(dependencies).to include(
          Dependabot::Dependency.new(
            name: "jason",
            version: "1.0.0",
            requirements: [{
              requirement: "~> 1.0",
              file: "apps/dependabot_business/mix.exs",
              groups: [],
              source: nil
            }],
            package_manager: "hex"
          )
        )
        expect(dependencies).to include(
          Dependabot::Dependency.new(
            name: "plug",
            version: "1.3.6",
            requirements: [
              {
                requirement: "1.3.6",
                file: "apps/dependabot_web/mix.exs",
                groups: [],
                source: nil
              },
              {
                requirement: "~> 1.3.0",
                file: "apps/dependabot_business/mix.exs",
                groups: [],
                source: nil
              }
            ],
            package_manager: "hex"
          )
        )
        expect(dependencies).to include(
          Dependabot::Dependency.new(
            name: "distillery",
            version: "1.5.2",
            requirements: [{
              requirement: "~> 1.5",
              file: "mix.exs",
              groups: [],
              source: nil
            }],
            package_manager: "hex"
          )
        )
      end
    end
  end
end
