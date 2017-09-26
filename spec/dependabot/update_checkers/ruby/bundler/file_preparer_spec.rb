# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/update_checkers/ruby/bundler/file_preparer"

RSpec.describe Dependabot::UpdateCheckers::Ruby::Bundler::FilePreparer do
  let(:preparer) do
    described_class.new(
      dependency_files: dependency_files,
      dependency: dependency,
      remove_git_source: remove_git_source
    )
  end

  let(:dependency_files) { [gemfile, lockfile] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: [],
      package_manager: "bundler"
    )
  end

  let(:version) { "df9f605d7111b6814fe493cf8f41de3f9f0978b2" }
  let(:dependency_name) { "business" }
  let(:remove_git_source) { false }

  let(:gemfile) do
    Dependabot::DependencyFile.new(content: gemfile_body, name: "Gemfile")
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(content: lockfile_body, name: "Gemfile.lock")
  end
  let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }
  let(:lockfile_body) { fixture("ruby", "lockfiles", "Gemfile.lock") }

  describe "#prepared_dependency_files" do
    subject(:prepared_dependency_files) { preparer.prepared_dependency_files }

    describe "the updated Gemfile" do
      subject { prepared_dependency_files.find { |f| f.name == "Gemfile" } }

      context "with a ~> matcher" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }
        let(:version) { "1.4.3" }

        its(:content) { is_expected.to include(%("business", '>= 1.4.3')) }
        its(:content) { is_expected.to include(%("statesman", "~> 1.2.0")) }
      end

      context "within a source block" do
        let(:gemfile_body) do
          "source 'https://example.com' do\n"\
          "  gem \"business\", \"~> 1.0\", require: true\n"\
          "end"
        end
        let(:version) { "1.4.3" }

        its(:content) { is_expected.to include(%("business", '>= 1.4.3')) }
      end

      context "with multiple requirements" do
        let(:version) { "1.4.3" }
        let(:gemfile_body) { %(gem "business", ">= 1", "< 3", require: true) }
        its(:content) do
          is_expected.to eq(%(gem "business", '>= 1.4.3', require: true))
        end

        context "given as an array" do
          let(:gemfile_body) do
            %(gem "business", [">= 1", "<3"], require: true)
          end
          its(:content) do
            is_expected.to eq(%(gem "business", '>= 1.4.3', require: true))
          end
        end
      end

      context "with a git source" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "git_source") }
        let(:version) { "df9f605d7111b6814fe493cf8f41de3f9f0978b2" }
        let(:dependency_name) { "prius" }

        its(:content) { is_expected.to include(%("prius", git:)) }

        context "and a version specified" do
          let(:gemfile_body) do
            fixture("ruby", "gemfiles", "git_source_with_version")
          end

          its(:content) { is_expected.to include(%("prius", '>= 0', git:)) }
        end

        context "that should be removed" do
          let(:remove_git_source) { true }
          its(:content) { is_expected.to include(%("prius"\n)) }
          its(:content) { is_expected.to include(%("que", git:)) }

          context "with a tag (i.e., multiple git-related arguments)" do
            let(:dependency_name) { "que" }
            its(:content) { is_expected.to include(%("que"\n)) }
          end

          context "with non-git tags at the start" do
            let(:gemfile_body) do
              %(gem "prius", "1.0.0", require: false, git: "git_url")
            end
            its(:content) do
              is_expected.to eq(%(gem "prius", '>= 0', require: false))
            end
          end

          context "with non-git tags at the end" do
            let(:gemfile_body) do
              %(gem "prius", "1.0.0", git: "git_url", require: false)
            end
            its(:content) do
              is_expected.to eq(%(gem "prius", '>= 0', require: false))
            end
          end

          context "with non-git tags on a subsequent line" do
            let(:gemfile_body) do
              %(gem "prius", "1.0.0", git: "git_url",\nrequire: false)
            end
            its(:content) do
              is_expected.to eq(%(gem "prius", '>= 0', require: false))
            end
          end

          context "with git tags on a subsequent line" do
            let(:gemfile_body) do
              %(gem "prius", "1.0.0", require: false,\ngit: "git_url")
            end
            its(:content) do
              is_expected.to eq(%(gem "prius", '>= 0', require: false))
            end
          end

          context "with a custom tag" do
            let(:gemfile_body) { %(gem "prius", "1.0.0", github: "git_url") }
            its(:content) { is_expected.to eq(%(gem "prius", '>= 0')) }
          end

          context "with a comment" do
            let(:gemfile_body) do
              %(gem "prius", "1.0.0", git: "git_url" # My gem)
            end
            its(:content) { is_expected.to eq(%(gem "prius", '>= 0' # My gem)) }
          end
        end
      end

      context "with a function call" do
        let(:gemfile_body) { "gem \"business\", version" }
        let(:version) { "1.4.3" }

        its(:content) { is_expected.to include(%("business", '>= 1.4.3')) }
      end
    end

    describe "the updated gemspec" do
      let(:dependency_files) { [gemfile, lockfile, gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          content: gemspec_body,
          name: "example.gemspec"
        )
      end
      let(:gemspec_body) { fixture("ruby", "gemspecs", "small_example") }
      let(:version) { "1.4.3" }

      subject do
        prepared_dependency_files.find { |f| f.name == "example.gemspec" }
      end

      its(:content) { is_expected.to include("'business'\n") }

      context "when the file requires sanitizing" do
        let(:gemspec_body) { fixture("ruby", "gemspecs", "with_require") }
        let(:dependency_name) { "gitlab" }

        its(:content) { is_expected.to include(%("gitlab"\n)) }
        its(:content) { is_expected.to_not include("require ") }
        its(:content) { is_expected.to include(%(version      = '0.0.1')) }
      end

      context "with multiple requirements" do
        let(:version) { "1.4.3" }
        let(:gemspec_body) { %(spec.add_dependency "business", ">= 1", "< 3") }
        its(:content) { is_expected.to eq(%(spec.add_dependency "business")) }

        context "given as an array" do
          let(:gemspec_body) do
            %(spec.add_dependency "business", [">= 1", "<3"])
          end
          its(:content) { is_expected.to eq(%(spec.add_dependency "business")) }
        end
      end

      context "with parentheses" do
        let(:version) { "1.4.3" }
        let(:gemspec_body) { %(spec.add_dependency("business", ">= 1", "< 3")) }
        its(:content) { is_expected.to eq(%(spec.add_dependency("business"))) }
      end
    end
  end
end
