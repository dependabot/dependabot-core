# frozen_string_literal: true

require "spec_helper"
require "dependabot/source"
require "dependabot/dependency_file"
require "dependabot/bundler/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Bundler::FileParser do
  it_behaves_like "a dependency file parser"

  let(:parser) do
    described_class.new(
      dependency_files: dependency_files,
      source: source,
      reject_external_code: reject_external_code
    )
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "dependabot-fixtures/bump",
      directory: "/"
    )
  end
  let(:dependency_files) { bundler_project_dependency_files("version_specified_gemfile") }
  let(:reject_external_code) { false }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "with a version specified" do
      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: "~> 1.4.0",
            file: "Gemfile",
            source: nil,
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("business") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
        its(:version) { is_expected.to eq("1.4.0") }
      end

      context "that is a pre-release with a dash" do
        let(:dependency_files) { bundler_project_dependency_files("prerelease_with_dash_gemfile") }

        its(:length) { is_expected.to eq(2) }

        describe "the first dependency" do
          subject { dependencies.first }
          let(:expected_requirements) do
            [{
              requirement: "~> 1.4.0-rc1",
              file: "Gemfile",
              source: nil,
              groups: [:default]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("business") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
          its(:version) { is_expected.to eq("1.4.0") }
        end
      end
    end

    context "with no version specified" do
      describe "the first dependency" do
        let(:dependency_files) { bundler_project_dependency_files("version_not_specified") }
        subject { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Gemfile",
            source: nil,
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("business") }
        its(:version) { is_expected.to eq("1.4.0") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with a version specified as between two constraints" do
      let(:dependency_files) { bundler_project_dependency_files("version_between_bounds_gemfile") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: "> 1.0.0, < 1.5.0",
            file: "Gemfile",
            source: nil,
            groups: [:default]
          }]
        end

        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with development dependencies" do
      let(:dependency_files) { bundler_project_dependency_files("development_dependencies") }
      its(:length) { is_expected.to eq(2) }

      describe "the last dependency" do
        subject { dependencies.last }
        let(:expected_requirements) do
          [{
            requirement: "~> 1.4.0",
            file: "Gemfile",
            source: nil,
            groups: %i(development test)
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("business") }
        its(:version) { is_expected.to eq("1.4.0") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "from a gems.rb and gems.locked" do
      let(:dependency_files) { bundler_project_dependency_files("version_specified_gems_rb") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: "~> 1.4.0",
            file: "gems.rb",
            source: nil,
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("business") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
        its(:version) { is_expected.to eq("1.4.0") }
      end
    end

    context "with a git dependency" do
      let(:dependency_files) { bundler_project_dependency_files("git_source") }

      its(:length) { is_expected.to eq(5) }

      describe "an untagged dependency", :bundler_v1_only do
        subject { dependencies.find { |d| d.name == "uk_phone_numbers" } }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Gemfile",
            source: {
              type: "git",
              url: "http://github.com/dependabot-fixtures/uk_phone_numbers",
              branch: nil,
              ref: "master"
            },
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:requirements) { is_expected.to eq(expected_requirements) }
        its(:version) do
          is_expected.to eq("1530024bd6a68d36ac18e04836ce110e0d433c36")
        end
      end

      describe "an untagged dependency", :bundler_v2_only do
        subject { dependencies.find { |d| d.name == "uk_phone_numbers" } }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Gemfile",
            source: {
              type: "git",
              url: "http://github.com/dependabot-fixtures/uk_phone_numbers",
              branch: nil,
              ref: nil
            },
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:requirements) { is_expected.to eq(expected_requirements) }
        its(:version) do
          is_expected.to eq("1530024bd6a68d36ac18e04836ce110e0d433c36")
        end
      end

      describe "a tagged dependency" do
        subject { dependencies.find { |d| d.name == "que" } }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Gemfile",
            source: {
              type: "git",
              url: "git@github.com:dependabot-fixtures/que",
              branch: nil,
              ref: "v0.11.6"
            },
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:requirements) { is_expected.to eq(expected_requirements) }
        its(:version) do
          is_expected.to eq("997d1a6ee76a1f254fd72ce16acbc8d347fcaee3")
        end
      end

      describe "a github dependency", :bundler_v1_only do
        let(:dependency_files) { bundler_project_dependency_files("github_source") }

        subject { dependencies.find { |d| d.name == "business" } }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Gemfile",
            source: {
              type: "git",
              url: "https://github.com/dependabot-fixtures/business.git",
              branch: nil,
              ref: "master"
            },
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:requirements) { is_expected.to eq(expected_requirements) }
        its(:version) do
          is_expected.to eq("d31e445215b5af70c1604715d97dd953e868380e")
        end
      end

      describe "a github dependency", :bundler_v2_only do
        let(:dependency_files) { bundler_project_dependency_files("github_source") }

        subject { dependencies.find { |d| d.name == "business" } }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Gemfile",
            source: {
              type: "git",
              url: "https://github.com/dependabot-fixtures/business.git",
              branch: nil,
              ref: nil
            },
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:requirements) { is_expected.to eq(expected_requirements) }
        its(:version) do
          is_expected.to eq("d31e445215b5af70c1604715d97dd953e868380e")
        end
      end

      context "with a subdependency of a git source", :bundler_v1_only do
        let(:dependency_files) { bundler_project_dependency_files("git_source_undeclared") }

        subject { dependencies.find { |d| d.name == "kaminari-actionview" } }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Gemfile",
            source: {
              type: "git",
              url: "https://github.com/dependabot-fixtures/kaminari",
              branch: nil,
              ref: "master"
            },
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("kaminari-actionview") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end

      context "with a subdependency of a git source", :bundler_v2_only do
        let(:dependency_files) { bundler_project_dependency_files("git_source_undeclared") }

        subject { dependencies.find { |d| d.name == "kaminari-actionview" } }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Gemfile",
            source: {
              type: "git",
              url: "https://github.com/dependabot-fixtures/kaminari",
              branch: nil,
              ref: nil
            },
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("kaminari-actionview") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "rejecting external code" do
      let(:reject_external_code) { true }

      context "with no git sources" do
        let(:dependency_files) { bundler_project_dependency_files("version_specified_gemfile") }

        it "does not raise exception" do
          expect { parser.parse }.not_to raise_error
        end
      end

      context "with a git source" do
        let(:dependency_files) { bundler_project_dependency_files("git_source") }

        it "raises exception" do
          expect { parser.parse }.to raise_error(::Dependabot::UnexpectedExternalCode)
        end
      end

      context "with a subdependency of a git source" do
        let(:dependency_files) { bundler_project_dependency_files("git_source_undeclared") }

        it "raises exception" do
          expect { parser.parse }.to raise_error(::Dependabot::UnexpectedExternalCode)
        end
      end
    end

    context "with a dependency that only appears in the lockfile" do
      let(:dependency_files) { bundler_project_dependency_files("subdependency") }

      its(:length) { is_expected.to eq(2) }
      it "is included" do
        expect(dependencies.map(&:name)).to include("i18n")
      end
    end

    context "with a dependency that doesn't appear in the lockfile" do
      let(:dependency_files) { bundler_project_dependency_files("platform_windows") }

      its(:length) { is_expected.to eq(1) }
      it "is not included" do
        expect(dependencies.map(&:name)).to_not include("statesman")
      end
    end

    context "with a path-based dependency" do
      let(:dependency_files) do
        bundler_project_dependency_files("path_source").tap do |files|
          gemspec = files.find { |f| f.name == "plugins/example/example.gemspec" }
          gemspec.support_file = true
        end
      end

      let(:expected_requirements) do
        [{
          requirement: ">= 0.9.0",
          file: "Gemfile",
          source: { type: "path" },
          groups: [:default]
        }]
      end

      its(:length) { is_expected.to eq(5) }

      it "includes the path dependency" do
        path_dep = dependencies.find { |dep| dep.name == "example" }
        expect(path_dep.requirements).to eq(expected_requirements)
      end

      it "includes the path dependency's sub-dependency" do
        sub_dep = dependencies.find { |dep| dep.name == "i18n" }
        expect(sub_dep.requirements).to eq([])
        expect(sub_dep.top_level?).to eq(false)
      end

      context "that comes from a .specification file" do
        let(:dependency_files) { bundler_project_dependency_files("version_specified_gemfile_specification") }

        it "includes the path dependency" do
          path_dep = dependencies.find { |dep| dep.name == "example" }
          expect(path_dep.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with a gem from a private gem source" do
      let(:dependency_files) { bundler_project_dependency_files("specified_source") }
      its(:length) { is_expected.to eq(2) }

      describe "the private dependency" do
        subject { dependencies.last }

        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Gemfile",
            source: {
              type: "rubygems",
              url: "https://SECRET_CODES@repo.fury.io/greysteil/"
            },
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("business") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with a gem from a plugin gem source" do
      let(:dependency_files) { bundler_project_dependency_files("specified_plugin_source") }

      it "raises a helpful error" do
        expect { parser.parse }.
          to raise_error do |error|
          expect(error.class).to eq(Dependabot::DependencyFileNotEvaluatable)
          expect(error.message).
            to include("No plugin sources available for aws-s3")
        end
      end
    end

    context "with a gem from the default source, specified as a block" do
      let(:dependency_files) { bundler_project_dependency_files("block_source_rubygems") }
      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Gemfile",
            source: nil,
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("statesman") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "when the Gemfile can't be evaluated" do
      let(:dependency_files) { bundler_project_dependency_files("unevaluatable_japanese_gemfile") }

      it "raises a helpful error" do
        expect { parser.parse }.
          to raise_error do |error|
          expect(error.class).to eq(Dependabot::DependencyFileNotEvaluatable)
          expect(error.message.encoding.to_s).to eq("UTF-8")
        end
      end

      context "because it contains an exec command" do
        let(:dependency_files) { bundler_project_dependency_files("exec_error_gemfile") }

        it "raises a helpful error" do
          expect { parser.parse }.
            to raise_error do |error|
            expect(error.message).
              to start_with("Error evaluating your dependency files")
            expect(error.class).
              to eq(Dependabot::DependencyFileNotEvaluatable)
          end
        end
      end
    end

    context "with a Gemfile that uses eval_gemfile" do
      let(:dependency_files) { bundler_project_dependency_files("eval_gemfile_gemfile") }

      its(:length) { is_expected.to eq(2) }
    end

    context "with a Gemfile that includes a require" do
      let(:dependency_files) { bundler_project_dependency_files("includes_requires_gemfile") }

      it "blows up with a useful error" do
        expect { parser.parse }.
          to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end

    context "with a Gemfile that includes a file with require_relative" do
      let(:dependency_files) do
        bundler_project_dependency_files("includes_require_relative_gemfile").map do |file|
          path = Pathname.new(file.name)
          file.name = File.basename(path)
          dir = File.dirname(path)
          file.directory = dir
          file.name = "../#{file.name}" if dir != "nested"
          file
        end
      end

      its(:length) { is_expected.to eq(2) }
    end

    context "with a Gemfile that imports a gemspec" do
      let(:dependency_files) { bundler_project_dependency_files("imports_gemspec") }

      it "doesn't include the gemspec dependency (i.e., itself)" do
        expect(dependencies.map(&:name)).to match_array(%w(business statesman))
      end

      context "with a gemspec from a specific path" do
        let(:dependency_files) { bundler_project_dependency_files("imports_gemspec_from_path") }

        it "fetches details from the gemspec" do
          expect(dependencies.map(&:name)).
            to match_array(%w(business statesman))
          expect(dependencies.first.name).to eq("business")
          expect(dependencies.first.requirements).
            to match_array(
              [{
                file: "Gemfile",
                requirement: "~> 1.4.0",
                groups: [:default],
                source: nil
              }, {
                file: "subdir/example.gemspec",
                requirement: "~> 1.0",
                groups: ["runtime"],
                source: nil
              }]
            )
        end

        context "with a gemspec with a float version number" do
          let(:dependency_files) { bundler_project_dependency_files("imports_gemspec_version_as_float") }

          it "includes the gemspec dependency" do
            expect(dependencies.map(&:name)).
              to match_array(%w(business statesman))
          end
        end
      end

      context "with an unparseable git dep that also appears in the gemspec", :bundler_v1_only do
        let(:dependency_files) { bundler_project_dependency_files("git_source_unparseable") }

        it "includes source details on the gemspec requirement" do
          expect(dependencies.map(&:name)).to match_array(%w(business))
          expect(dependencies.first.name).to eq("business")
          expect(dependencies.first.version).
            to eq("1378a2b0b446d991b7567efbc7eeeed2720e4d8f")
          expect(dependencies.first.requirements).
            to match_array(
              [{
                file: "example.gemspec",
                requirement: "~> 1.0",
                groups: ["runtime"],
                source: {
                  type: "git",
                  url: "git@github.com:dependabot-fixtures/business",
                  branch: nil,
                  ref: "master"
                }
              }]
            )
        end

        it "includes source details on the gemspec requirement", :bundler_v2_only do
          expect(dependencies.map(&:name)).to match_array(%w(business))
          expect(dependencies.first.name).to eq("business")
          expect(dependencies.first.version).
            to eq("1378a2b0b446d991b7567efbc7eeeed2720e4d8f")
          expect(dependencies.first.requirements).
            to match_array(
              [{
                file: "example.gemspec",
                requirement: "~> 1.0",
                groups: ["runtime"],
                source: {
                  type: "git",
                  url: "git@github.com:dependabot-fixtures/business",
                  branch: nil,
                  ref: nil
                }
              }]
            )
        end
      end

      context "with two gemspecs" do
        let(:dependency_files) { bundler_project_dependency_files("imports_two_gemspecs") }

        it "fetches details from both gemspecs" do
          expect(dependencies.map(&:name)).
            to match_array(%w(business statesman))
          expect(dependencies.map(&:requirements)).
            to match_array(
              [
                [{
                  requirement: "~> 1.0",
                  groups: ["runtime"],
                  source: nil,
                  file: "example.gemspec"
                }],
                [{
                  requirement: "~> 1.0",
                  groups: ["runtime"],
                  source: nil,
                  file: "example2.gemspec"
                }]
              ]
            )
        end
      end

      context "with a large gemspec" do
        let(:dependency_files) { bundler_project_dependency_files("imports_gemspec_imports_gemspec_large") }

        it "includes details of each declaration" do
          expect(dependencies.count(&:top_level?)).to eq(13)
        end

        it "includes details of each sub-dependency" do
          expect(dependencies.count { |dep| !dep.top_level? }).to eq(23)

          diff_lcs = dependencies.find { |d| d.name == "diff-lcs" }
          expect(diff_lcs.subdependency_metadata).to eq([{ production: false }])

          addressable = dependencies.find { |d| d.name == "addressable" }
          expect(addressable.subdependency_metadata).
            to eq([{ production: true }])
        end

        describe "a runtime gemspec dependency" do
          subject { dependencies.find { |dep| dep.name == "gitlab" } }
          let(:expected_requirements) do
            [{
              requirement: "~> 4.1",
              file: "example.gemspec",
              source: nil,
              groups: ["runtime"]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("gitlab") }
          its(:version) { is_expected.to eq("4.2.0") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end

        describe "a development gemspec dependency" do
          subject { dependencies.find { |dep| dep.name == "webmock" } }
          let(:expected_requirements) do
            [{
              requirement: "~> 2.3.1",
              file: "example.gemspec",
              source: nil,
              groups: ["development"]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("webmock") }
          its(:version) { is_expected.to eq("2.3.2") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end

        context "that needs to be sanitized" do
          let(:dependency_files) { bundler_project_dependency_files("imports_gemspec_with_require") }

          it "includes details of each declaration" do
            expect(dependencies.count(&:top_level?)).to eq(13)
          end
        end

        context "that can't be evaluated" do
          let(:dependency_files) { bundler_project_dependency_files("imports_gemspec_unevaluatable") }

          it "raises a helpful error" do
            expect { parser.parse }.
              to raise_error(Dependabot::DependencyFileNotEvaluatable)
          end
        end
      end
    end

    context "with a gemspec that loads dependencies from another gemspec dynamically" do
      let(:dependency_files) { bundler_project_dependency_files("gemspec_loads_another") }

      describe "a development dependency loaded from an external gemspec" do
        subject { dependencies.find { |d| d.name == "rake" } }

        it "is only loaded with its own gemspec as requirement" do
          expect(subject.name).to eq("rake")
          expect(subject.requirements.size).to eq(1)
          expect(subject.requirements.first[:file]).to eq("another.gemspec")
        end
      end
    end

    context "with a gemspec and Gemfile (no lockfile)" do
      let(:dependency_files) { bundler_project_dependency_files("imports_gemspec_no_lockfile") }
      its(:length) { is_expected.to eq(13) }

      context "when a dependency appears in both" do
        let(:dependency_files) { bundler_project_dependency_files("imports_gemspec_git_override_no_lockfile") }

        its(:length) { is_expected.to eq(1) }

        describe "the first dependency" do
          subject { dependencies.first }
          let(:expected_requirements) do
            [
              {
                requirement: "~> 1.0",
                file: "example.gemspec",
                source: nil,
                groups: ["runtime"]
              },
              {
                requirement: "~> 1.4.0",
                file: "Gemfile",
                source: {
                  type: "git",
                  url: "https://github.com/dependabot-fixtures/business",
                  branch: nil,
                  ref: nil
                },
                groups: [:default]
              }
            ]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("business") }
          its(:version) { is_expected.to be_nil }
          its(:requirements) do
            is_expected.to match_array(expected_requirements)
          end
        end
      end
    end

    context "with only a gemspec" do
      let(:dependency_files) { bundler_project_dependency_files("gemspec_no_lockfile") }

      its(:length) { is_expected.to eq(11) }

      describe "the last dependency" do
        subject { dependencies.last }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "example.gemspec",
            source: nil,
            groups: ["development"]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("rake") }
        its(:version) { is_expected.to be_nil }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end

      context "that needs to be sanitized" do
        let(:dependency_files) { bundler_project_dependency_files("gemspec_with_require_no_lockfile") }
        its(:length) { is_expected.to eq(11) }
      end
    end

    context "with only a gemfile" do
      let(:dependency_files) { bundler_project_dependency_files("version_specified_no_lockfile") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: "~> 1.4.0",
            file: "Gemfile",
            source: nil,
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("business") }
        its(:version) { is_expected.to be_nil }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end

      context "with a dependency for an alternative platform" do
        let(:dependency_files) { bundler_project_dependency_files("platform_windows_no_lockfile") }

        its(:length) { is_expected.to eq(1) }
        it "is not included" do
          expect(dependencies.map(&:name)).to_not include("statesman")
        end
      end
    end

    it "instruments the package manager version" do
      events = []
      Dependabot.subscribe(Dependabot::Notifications::FILE_PARSER_PACKAGE_MANAGER_VERSION_PARSED) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      parser.parse

      expect(events.last.payload).to eq(
        { ecosystem: "bundler", package_managers: { "bundler" => PackageManagerHelper.bundler_version } }
      )
    end
  end
end
