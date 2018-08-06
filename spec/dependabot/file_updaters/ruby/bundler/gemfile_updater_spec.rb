# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/ruby/bundler/gemfile_updater"

RSpec.describe Dependabot::FileUpdaters::Ruby::Bundler::GemfileUpdater do
  include_context "stub rubygems compact index"

  let(:updater) do
    described_class.new(dependencies: dependencies, gemfile: gemfile)
  end
  let(:dependencies) { [dependency] }
  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: gemfile_body
    )
  end
  let(:gemfile_body) { fixture("ruby", "gemfiles", gemfile_fixture_name) }
  let(:gemfile_fixture_name) { "Gemfile" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      previous_version: dependency_previous_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      package_manager: "bundler"
    )
  end
  let(:dependency_name) { "business" }
  let(:dependency_version) { "1.5.0" }
  let(:dependency_previous_version) { "1.4.0" }
  let(:requirements) do
    [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }]
  end
  let(:previous_requirements) do
    [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
  end

  describe "#updated_gemfile_content" do
    subject(:updated_gemfile_content) { updater.updated_gemfile_content }

    context "when no change is required" do
      let(:gemfile_fixture_name) { "version_not_specified" }
      let(:requirements) do
        [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
      end
      let(:previous_requirements) do
        [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
      end
      it { is_expected.to eq(gemfile_body) }
    end

    context "when the full version is specified" do
      let(:gemfile_fixture_name) { "version_specified" }
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 1.5.0",
          groups: [],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 1.4.0",
          groups: [],
          source: nil
        }]
      end
      it { is_expected.to include("\"business\", \"~> 1.5.0\"") }
      it { is_expected.to include("\"statesman\", \"~> 1.2.0\"") }
    end

    context "when updating a sub-dependency" do
      let(:gemfile_fixture_name) { "subdependency" }
      let(:lockfile_fixture_name) { "subdependency.lock" }
      let(:dependency_name) { "i18n" }
      let(:dependency_version) { "1.6.0.beta" }
      let(:dependency_previous_version) { "0.7.0.beta1" }
      let(:requirements) { [] }
      let(:previous_requirements) { [] }

      it { is_expected.to eq(gemfile_body) }
    end

    context "when a pre-release is specified" do
      let(:gemfile_fixture_name) { "prerelease_specified" }
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 1.5.0",
          groups: [],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 1.4.0.rc1",
          groups: [],
          source: nil
        }]
      end
      it { is_expected.to include "\"business\", \"~> 1.5.0\"" }
    end

    context "when the minor version is specified" do
      let(:gemfile_fixture_name) { "minor_version_specified" }
      let(:requirements) do
        [{ file: "Gemfile", requirement: "~> 1.5", groups: [], source: nil }]
      end
      let(:previous_requirements) do
        [{ file: "Gemfile", requirement: "~> 1.4", groups: [], source: nil }]
      end
      it { is_expected.to include "\"business\", \"~> 1.5\"" }
      it { is_expected.to include "\"statesman\", \"~> 1.2\"" }
    end

    context "with a gem whose name includes a number" do
      let(:gemfile_fixture_name) { "gem_with_number" }
      let(:lockfile_fixture_name) { "gem_with_number.lock" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "i18n",
          version: "0.5.0",
          requirements: [{
            file: "Gemfile",
            requirement: "~> 0.5.0",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "Gemfile",
            requirement: "~> 0.4.0",
            groups: [],
            source: nil
          }],
          package_manager: "bundler"
        )
      end
      it { is_expected.to include "\"i18n\", \"~> 0.5.0\"" }
    end

    context "when there is a comment" do
      let(:gemfile_fixture_name) { "comments" }
      it do
        is_expected.to include "\"business\", \"~> 1.5.0\"   # Business time"
      end
    end

    context "when the previous version used string interpolation" do
      let(:gemfile_fixture_name) { "interpolated_version" }
      it { is_expected.to include "\"business\", \"~> #" }
    end

    context "when the previous version used a function" do
      let(:gemfile_fixture_name) { "function_version" }
      it { is_expected.to include "\"business\", version" }
    end

    context "with multiple dependencies" do
      let(:gemfile_fixture_name) { "version_conflict" }
      let(:lockfile_fixture_name) { "version_conflict.lock" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "rspec-mocks",
            version: "3.6.0",
            previous_version: "3.5.0",
            requirements: requirements,
            previous_requirements: previous_requirements,
            package_manager: "bundler"
          ),
          Dependabot::Dependency.new(
            name: "rspec-support",
            version: "3.6.0",
            previous_version: "3.5.0",
            requirements: requirements,
            previous_requirements: previous_requirements,
            package_manager: "bundler"
          )
        ]
      end
      let(:requirements) do
        [{ file: "Gemfile", requirement: "3.6.0", groups: [], source: nil }]
      end
      let(:previous_requirements) do
        [{ file: "Gemfile", requirement: "3.5.0", groups: [], source: nil }]
      end

      it "updates both dependencies" do
        expect(updated_gemfile_content).
          to include("\"rspec-mocks\", \"3.6.0\"")
        expect(updated_gemfile_content).
          to include("\"rspec-support\", \"3.6.0\"")
      end
    end

    context "with a gem that has a git source" do
      let(:gemfile_fixture_name) { "git_source_with_version" }
      let(:lockfile_fixture_name) { "git_source_with_version.lock" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: "c170ea081c121c00ed6fe8764e3557e731454b9d",
          previous_version: "c5bf1bd47935504072ac0eba1006cf4d67af6a7a",
          requirements: requirements,
          previous_requirements: previous_requirements,
          package_manager: "bundler"
        )
      end
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 1.14.0",
          groups: [],
          source: {
            type: "git",
            url: "http://github.com/gocardless/business"
          }
        }]
      end
      let(:previous_requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 1.0.0",
          groups: [],
          source: {
            type: "git",
            url: "http://github.com/gocardless/business"
          }
        }]
      end

      it { is_expected.to include "\"business\", \"~> 1.14.0\", git" }

      context "that should have its tag updated" do
        let(:gemfile_body) do
          %(gem "business", "~> 1.0.0", ) +
            %(git: "https://github.com/gocardless/business", tag: "v1.0.0")
        end
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.8.0",
            groups: [],
            source: {
              type: "git",
              url: "http://github.com/gocardless/business",
              ref: "v1.8.0"
            }
          }]
        end

        let(:expected_string) do
          %(gem "business", "~> 1.8.0", ) +
            %(git: "https://github.com/gocardless/business", tag: "v1.8.0")
        end

        it { is_expected.to eq(expected_string) }
      end

      context "that should be removed" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.8.0",
            previous_version: "c5bf1bd47935504072ac0eba1006cf4d67af6a7a",
            requirements: requirements,
            previous_requirements: previous_requirements,
            package_manager: "bundler"
          )
        end
        let(:requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.8.0",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to include "\"business\", \"~> 1.8.0\"\n" }

        context "with a tag (i.e., multiple git-related arguments)" do
          let(:gemfile_body) do
            %(gem "business", git: "git_url", tag: "old_tag")
          end
          it { is_expected.to eq(%(gem "business")) }
        end

        context "with non-git args at the start" do
          let(:gemfile_body) do
            %(gem "business", "1.0.0", require: false, git: "git_url")
          end
          it do
            is_expected.to eq(%(gem "business", "~> 1.8.0", require: false))
          end
        end

        context "with non-git args at the end" do
          let(:gemfile_body) do
            %(gem "business", "1.0.0", git: "git_url", require: false)
          end
          it do
            is_expected.to eq(%(gem "business", "~> 1.8.0", require: false))
          end
        end

        context "with non-git args on a subsequent line" do
          let(:gemfile_body) do
            %(gem("business", "1.0.0", git: "git_url",\nrequire: false))
          end
          it do
            is_expected.to eq(%(gem("business", "~> 1.8.0", require: false)))
          end
        end

        context "with git args on a subsequent line" do
          let(:gemfile_body) do
            %(gem "business", '1.0.0', require: false,\ngit: "git_url")
          end
          it do
            is_expected.to eq(%(gem "business", '~> 1.8.0', require: false))
          end
        end

        context "with a custom arg" do
          let(:gemfile_body) { %(gem "business", "1.0.0", github: "git_url") }
          it { is_expected.to eq(%(gem "business", "~> 1.8.0")) }
        end

        context "with a comment" do
          let(:gemfile_body) { %(gem "business", git: "git_url" # My gem) }
          it { is_expected.to eq(%(gem "business" # My gem)) }
        end
      end
    end

    context "when the new (and old) requirement is a range" do
      let(:gemfile_fixture_name) { "version_between_bounds" }
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "> 1.0.0, < 1.6.0",
          groups: [],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "Gemfile",
          requirement: "> 1.0.0, < 1.5.0",
          groups: [],
          source: nil
        }]
      end

      it { is_expected.to include "\"business\", \"> 1.0.0\", \"< 1.6.0\"" }
    end
  end
end
