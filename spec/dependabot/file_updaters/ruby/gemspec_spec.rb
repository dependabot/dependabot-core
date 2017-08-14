# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/ruby/gemspec"
require "dependabot/shared_helpers"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Ruby::Gemspec do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: [gemspec],
      dependency: dependency,
      github_access_token: "token"
    )
  end
  let(:gemspec) do
    Dependabot::DependencyFile.new(
      content: gemspec_body,
      name: "example.gemspec"
    )
  end
  let(:gemspec_body) do
    fixture("ruby", "gemspecs", "example")
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "octokit",
      version: "5.1.0",
      requirement: ">= 4.6, < 6.0",
      package_manager: "gemspec",
      groups: []
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated gemspec" do
      subject(:updated_gemspec) do
        updated_files.find { |f| f.name == "example.gemspec" }
      end

      its(:content) do
        is_expected.to include(%("octokit", ">= 4.6", "< 6.0"\n))
      end

      context "with a runtime dependency" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "bundler",
            version: "5.1.0",
            requirement: ">= 4.6, < 6.0",
            package_manager: "gemspec",
            groups: []
          )
        end

        its(:content) do
          is_expected.to include(%("bundler", ">= 4.6", "< 6.0"\n))
        end
      end

      context "with a development dependency" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "webmock",
            version: "5.1.0",
            requirement: ">= 4.6, < 6.0",
            package_manager: "gemspec",
            groups: []
          )
        end

        its(:content) do
          is_expected.to include(%("webmock", ">= 4.6", "< 6.0"\n))
        end
      end

      context "with an array of requirements" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "excon",
            version: "5.1.0",
            requirement: ">= 4.6, < 6.0",
            package_manager: "gemspec",
            groups: []
          )
        end

        its(:content) do
          is_expected.to include(%("excon", ">= 4.6", "< 6.0"\n))
        end
      end

      context "with brackets around the requirements" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "gemnasium-parser",
            version: "5.1.0",
            requirement: ">= 4.6, < 6.0",
            package_manager: "gemspec",
            groups: []
          )
        end

        its(:content) do
          is_expected.to include(%("gemnasium-parser", ">= 4.6", "< 6.0"\n))
        end
      end

      context "with single quotes" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "gems",
            version: "5.1.0",
            requirement: ">= 1.0, < 3.0",
            package_manager: "gemspec",
            groups: []
          )
        end

        its(:content) do
          is_expected.to include(%('gems', '>= 1.0', '< 3.0'\n))
        end
      end
    end
  end
end
