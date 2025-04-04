# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/hex/file_parser"
require "dependabot/hex/version"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Hex::FileParser do
  let(:reject_external_code) { false }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:parser) do
    described_class.new(
      dependency_files: files,
      source: source,
      reject_external_code: reject_external_code
    )
  end
  let(:lockfile_fixture_name) { "minor_version" }
  let(:mixfile_fixture_name) { "minor_version" }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "mix.lock",
      content: fixture("lockfiles", lockfile_fixture_name)
    )
  end
  let(:mixfile) do
    Dependabot::DependencyFile.new(
      name: "mix.exs",
      content: fixture("mixfiles", mixfile_fixture_name)
    )
  end
  let(:files) { [mixfile, lockfile] }

  it_behaves_like "a dependency file parser"

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "without a lockfile" do
      let(:files) { [mixfile] }

      its(:length) { is_expected.to eq(2) }

      describe "the last dependency" do
        subject(:dependency) { dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("plug")
          expect(dependency.version).to be_nil
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
          expect(dependency.version)
            .to eq("a89054cf71c5ee9e780998e5acb2a78fd3419dd9")
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
                url: "https://github.com/dependabot-fixtures/phoenix.git",
                branch: "master",
                ref: "v1.2.0"
              }
            }],
            package_manager: "hex"
          )
        )
      end

      context "with a tag (rather than a ref)" do
        let(:mixfile_fixture_name) { "git_source_tag_can_update" }
        let(:lockfile_fixture_name) { "git_source_tag_can_update" }

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
                  url: "https://github.com/dependabot-fixtures/phoenix.git",
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

    context "with hex v0.20.2+" do
      let(:mixfile_fixture_name) { "minor_version" }
      let(:lockfile_fixture_name) { "hex_version_0_20_2" }

      its(:length) { is_expected.to eq(2) }
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

    context "with an unevaluatable mixfile" do
      let(:mixfile_fixture_name) { "unevaluatable" }
      let(:lockfile_fixture_name) { "minor_version" }

      it "raises a helpful error" do
        expect { parser.parse }
          .to raise_error do |error|
            expect(error.class).to eq(Dependabot::DependencyFileNotEvaluatable)
          end
      end
    end

    context "with a call to read a version file" do
      let(:mixfile_fixture_name) { "loads_file" }
      let(:lockfile_fixture_name) { "exact_version" }

      its(:length) { is_expected.to eq(2) }
    end

    context "with a call to read a version file in a support file" do
      let(:mixfile_fixture_name) { "loads_file_with_require" }
      let(:lockfile_fixture_name) { "exact_version" }
      let(:files) { [mixfile, lockfile, support_file] }
      let(:support_file) do
        Dependabot::DependencyFile.new(
          name: "module_version.ex",
          content: fixture("support_files", "module_version"),
          support_file: true
        )
      end

      its(:length) { is_expected.to eq(2) }
    end

    context "with a call to eval a support file" do
      let(:mixfile_fixture_name) { "loads_file_with_eval" }
      let(:lockfile_fixture_name) { "exact_version" }
      let(:files) { [mixfile, lockfile, support_file] }
      let(:support_file) do
        Dependabot::DependencyFile.new(
          name: "version",
          content: fixture("support_files", "version"),
          support_file: true
        )
      end

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
          content: fixture("mixfiles", "dependabot_business")
        )
      end
      let(:sub_mixfile2) do
        Dependabot::DependencyFile.new(
          name: "apps/dependabot_web/mix.exs",
          content: fixture("mixfiles", "dependabot_web")
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

        plug_expectation = Dependabot::Dependency.new(
          name: "plug",
          version: "1.3.6",
          requirements: [{
            requirement: "~> 1.3.0",
            file: "apps/dependabot_business/mix.exs",
            groups: [],
            source: nil
          }, {
            requirement: "1.3.6",
            file: "apps/dependabot_web/mix.exs",
            groups: [],
            source: nil
          }],
          package_manager: "hex"
        )

        plug_dep = dependencies.find { |d| d.name == "plug" }

        expect(plug_dep.name).to eq(plug_expectation.name)
        expect(plug_dep.version).to eq(plug_expectation.version)
        expect(plug_dep.requirements).to match_array(plug_expectation.requirements)
        expect(plug_dep.package_manager).to eq(plug_expectation.package_manager)

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

    context "with a nerves project" do
      let(:mixfile_fixture_name) { "nerves" }

      it "parses the dependencies correctly" do
        expect(dependencies).to include(
          Dependabot::Dependency.new(
            name: "nerves",
            requirements: [{
              requirement: "~> 1.7.4",
              file: "mix.exs",
              groups: [],
              source: nil
            }],
            package_manager: "hex"
          )
        )
      end
    end

    context "with reject_external_code" do
      let(:reject_external_code) { true }

      it "raises UnexpectedExternalCode" do
        expect { dependencies }.to raise_error(Dependabot::UnexpectedExternalCode)
      end
    end
  end

  describe "#ecosystem" do
    subject(:ecosystem) { parser.ecosystem }

    it "has the correct name" do
      expect(ecosystem.name).to eq "hex"
    end

    describe "#package_manager" do
      subject(:package_manager) { ecosystem.package_manager }

      it "returns the correct package manager" do
        expect(package_manager.name).to eq "hex"
        expect(package_manager.requirement).to be_nil
        expect(package_manager.version.to_s).to eq "2.0.6"
      end
    end

    describe "#language" do
      subject(:language) { ecosystem.language }

      it "returns the correct language" do
        expect(language.name).to eq "elixir"
        expect(language.requirement).to be_nil
        expect(language.version.to_s).to eq "1.18.1"
      end
    end
  end
end
