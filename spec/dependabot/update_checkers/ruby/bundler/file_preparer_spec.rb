# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/update_checkers/ruby/bundler/file_preparer"

RSpec.describe Dependabot::UpdateCheckers::Ruby::Bundler::FilePreparer do
  let(:preparer) do
    described_class.new(
      dependency_files: dependency_files,
      dependency: dependency
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
        let(:gemfile_body) do
          %(gem "business", ">= 1", "< 3", require: true)
        end
        its(:content) do
          # TODO: This is sloppy, but fine for the update checker
          is_expected.
            to eq(%(gem "business", '>= 1.4.3', '>= 1.4.3', require: true))
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

      its(:content) { is_expected.to include(%('business', ">= 0")) }

      context "when the file requires sanitizing" do
        let(:gemspec_body) { fixture("ruby", "gemspecs", "with_require") }
        let(:dependency_name) { "gitlab" }

        its(:content) { is_expected.to include(%("gitlab", ">= 0")) }
        its(:content) { is_expected.to_not include("require ") }
        its(:content) { is_expected.to include(%(version      = '0.0.1')) }
      end
    end
  end
end
