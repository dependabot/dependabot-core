# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/ruby/bundler"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Ruby::Bundler do
  it_behaves_like "a dependency file parser"

  let(:files) { [gemfile, lockfile] }
  let(:gemfile) do
    Dependabot::DependencyFile.new(name: "Gemfile", content: gemfile_body)
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "Gemfile.lock", content: lockfile_body)
  end
  let(:parser) { described_class.new(dependency_files: files, repo: "org/nm") }
  let(:gemfile_body) { fixture("ruby", "gemfiles", gemfile_fixture_name) }
  let(:lockfile_body) { fixture("ruby", "lockfiles", lockfile_fixture_name) }
  let(:gemfile_fixture_name) { "version_specified" }
  let(:lockfile_fixture_name) { "Gemfile.lock" }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "with a version specified" do
      let(:gemfile_fixture_name) { "version_specified" }

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
        it { is_expected.to be_production }
        its(:name) { is_expected.to eq("business") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
        its(:version) { is_expected.to eq("1.4.0") }
      end
    end

    context "with no version specified" do
      let(:gemfile_fixture_name) { "version_not_specified" }
      let(:lockfile_fixture_name) { "version_not_specified.lock" }

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
        its(:name) { is_expected.to eq("business") }
        its(:version) { is_expected.to eq("1.4.0") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with a version specified as between two constraints" do
      let(:gemfile_fixture_name) { "version_between_bounds" }
      let(:lockfile_fixture_name) { "Gemfile.lock" }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: "< 1.5.0, > 1.0.0",
            file: "Gemfile",
            source: nil,
            groups: [:default]
          }]
        end

        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with development dependencies" do
      let(:gemfile_fixture_name) { "development_dependencies" }
      let(:lockfile_fixture_name) { "development_dependencies.lock" }

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
        it { is_expected.to_not be_production }
        its(:name) { is_expected.to eq("business") }
        its(:version) { is_expected.to eq("1.4.0") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with a git dependency" do
      let(:gemfile_fixture_name) { "git_source" }
      let(:lockfile_fixture_name) { "git_source.lock" }

      its(:length) { is_expected.to eq(5) }

      describe "an untagged dependency" do
        subject { dependencies.find { |d| d.name == "uk_phone_numbers" } }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Gemfile",
            source: {
              type: "git",
              url: "http://github.com/gocardless/uk_phone_numbers",
              branch: "master",
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

      describe "a tagged dependency" do
        subject { dependencies.find { |d| d.name == "que" } }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Gemfile",
            source: {
              type: "git",
              url: "git@github.com:gocardless/que",
              branch: "master",
              ref: "v0.11.7"
            },
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:requirements) { is_expected.to eq(expected_requirements) }
        its(:version) do
          is_expected.to eq("5bfb6d149c410801f194da7ceb3b2bdc5e8b75f3")
        end
      end

      describe "a github dependency" do
        let(:gemfile_fixture_name) { "github_source" }
        let(:lockfile_fixture_name) { "github_source.lock" }

        subject { dependencies.find { |d| d.name == "business" } }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Gemfile",
            source: {
              type: "git",
              url: "git://github.com/gocardless/business.git",
              branch: "master",
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

      context "with a subdependency of a git source" do
        let(:lockfile_fixture_name) { "git_source_undeclared.lock" }
        let(:gemfile_fixture_name) { "git_source_undeclared" }

        subject { dependencies.find { |d| d.name == "kaminari-actionview" } }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Gemfile",
            source: {
              type: "git",
              url: "https://github.com/kaminari/kaminari",
              branch: "master",
              ref: "master"
            },
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("kaminari-actionview") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with a dependency that only appears in the lockfile" do
      let(:gemfile_fixture_name) { "subdependency" }
      let(:lockfile_fixture_name) { "subdependency.lock" }

      its(:length) { is_expected.to eq(2) }
      it "is included" do
        expect(dependencies.map(&:name)).to include("i18n")
      end
    end

    context "with a dependency that doesn't appear in the lockfile" do
      let(:gemfile_fixture_name) { "platform_windows" }
      let(:lockfile_fixture_name) { "platform_windows.lock" }

      its(:length) { is_expected.to eq(1) }
      it "is not included" do
        expect(dependencies.map(&:name)).to_not include("statesman")
      end
    end

    context "with a path-based dependency" do
      let(:files) { [gemfile, lockfile, gemspec] }
      let(:gemfile_fixture_name) { "path_source" }
      let(:lockfile_fixture_name) { "path_source.lock" }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          name: "plugins/example/example.gemspec",
          content: fixture("ruby", "gemspecs", "example")
        )
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
    end

    context "with a gem from a private gem source" do
      let(:lockfile_fixture_name) { "specified_source.lock" }
      let(:gemfile_fixture_name) { "specified_source" }

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

    context "with a gem from the default source, specified as a block" do
      let(:lockfile_fixture_name) { "block_source_rubygems.lock" }
      let(:gemfile_fixture_name) { "block_source_rubygems" }

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
      let(:gemfile_fixture_name) { "unevaluatable_japanese" }
      let(:lockfile_fixture_name) { "Gemfile.lock" }

      it "raises a helpful error" do
        expect { parser.parse }.
          to raise_error do |error|
            expect(error.class).to eq(Dependabot::DependencyFileNotEvaluatable)
            expect(error.message.encoding.to_s).to eq("UTF-8")
          end
      end
    end

    context "with a Gemfile that uses eval_gemfile" do
      let(:files) { [gemfile, lockfile, evaled_gemfile] }
      let(:gemfile_fixture_name) { "eval_gemfile" }
      let(:evaled_gemfile) do
        Dependabot::DependencyFile.new(
          name: "backend/Gemfile",
          content: fixture("ruby", "gemfiles", "only_statesman")
        )
      end
      let(:lockfile_fixture_name) { "Gemfile.lock" }

      its(:length) { is_expected.to eq(2) }
    end

    context "with a Gemfile that includes a require" do
      let(:gemfile_fixture_name) { "includes_requires" }
      let(:lockfile_fixture_name) { "Gemfile.lock" }

      it "blows up with a useful error" do
        expect { parser.parse }.
          to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end

    context "with a Gemfile that imports a gemspec" do
      let(:files) { [gemfile, lockfile, gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          name: "example.gemspec",
          content: gemspec_content
        )
      end
      let(:gemfile_fixture_name) { "imports_gemspec" }
      let(:lockfile_fixture_name) { "imports_gemspec.lock" }
      let(:gemspec_content) { fixture("ruby", "gemspecs", "small_example") }

      it "doesn't include the gemspec dependency (i.e., itself)" do
        expect(dependencies.map(&:name)).to match_array(%w(business statesman))
      end

      context "with a large gemspec" do
        let(:gemspec_content) { fixture("ruby", "gemspecs", "example") }
        let(:lockfile_fixture_name) { "imports_gemspec_large.lock" }

        it "includes details of each declaration" do
          expect(dependencies.select(&:top_level?).count).to eq(13)
        end

        it "includes details of each sub-dependency" do
          expect(dependencies.reject(&:top_level?).count).to eq(23)
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
          it { is_expected.to be_production }
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
          let(:gemspec_content) { fixture("ruby", "gemspecs", "with_require") }
          it "includes details of each declaration" do
            expect(dependencies.select(&:top_level?).count).to eq(13)
          end
        end

        context "that can't be evaluated" do
          let(:gemspec_content) { fixture("ruby", "gemspecs", "unevaluatable") }

          it "raises a helpful error" do
            expect { parser.parse }.
              to raise_error(Dependabot::DependencyFileNotEvaluatable)
          end
        end
      end
    end

    context "with a gemspec and Gemfile (no lockfile)" do
      let(:files) { [gemspec, gemfile] }

      let(:gemspec) do
        Dependabot::DependencyFile.new(
          name: "example.gemspec",
          content: gemspec_content
        )
      end
      let(:gemspec_content) { fixture("ruby", "gemspecs", "example") }
      let(:gemfile_fixture_name) { "imports_gemspec" }

      its(:length) { is_expected.to eq(13) }

      context "when a dependency appears in both" do
        let(:gemfile_fixture_name) { "imports_gemspec_git_override" }
        let(:gemspec_content) { fixture("ruby", "gemspecs", "small_example") }

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
                  url: "https://github.com/gocardless/business",
                  branch: "master",
                  ref: "master"
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
      let(:files) { [gemspec] }

      let(:gemspec) do
        Dependabot::DependencyFile.new(
          name: "example.gemspec",
          content: gemspec_content
        )
      end
      let(:gemspec_content) { fixture("ruby", "gemspecs", "example") }

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
        let(:gemspec_content) { fixture("ruby", "gemspecs", "with_require") }
        its(:length) { is_expected.to eq(11) }
      end
    end

    context "with only a gemfile" do
      let(:files) { [gemfile] }
      let(:gemfile_fixture_name) { "version_specified" }

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
        let(:gemfile_fixture_name) { "platform_windows" }

        its(:length) { is_expected.to eq(1) }
        it "is not included" do
          expect(dependencies.map(&:name)).to_not include("statesman")
        end
      end
    end
  end
end
