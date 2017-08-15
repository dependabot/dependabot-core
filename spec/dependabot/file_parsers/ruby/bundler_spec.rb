# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/ruby/bundler"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Ruby::Bundler do
  it_behaves_like "a dependency file parser"

  let(:files) { [gemfile, lockfile] }
  let(:gemfile) do
    Dependabot::DependencyFile.new(name: "Gemfile", content: gemfile_content)
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile.lock",
      content: lockfile_content
    )
  end
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "with a version specified" do
      let(:gemfile_content) { fixture("ruby", "gemfiles", "version_specified") }
      let(:lockfile_content) { fixture("ruby", "lockfiles", "Gemfile.lock") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("business") }
        its(:requirement) { is_expected.to eq("~> 1.4.0") }
        its(:version) { is_expected.to eq("1.4.0") }
        its(:groups) { is_expected.to eq(%i(default)) }
      end
    end

    context "with no version specified" do
      let(:gemfile_content) do
        fixture("ruby", "gemfiles", "version_not_specified")
      end
      let(:lockfile_content) do
        fixture("ruby", "lockfiles", "version_not_specified.lock")
      end

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("business") }
        its(:version) { is_expected.to eq("1.4.0") }
        its(:requirement) { is_expected.to eq(">= 0") }
        its(:groups) { is_expected.to eq(%i(default)) }
      end
    end

    context "with a version specified as between two constraints" do
      let(:gemfile_content) do
        fixture("ruby", "gemfiles", "version_between_bounds")
      end
      let(:lockfile_content) { fixture("ruby", "lockfiles", "Gemfile.lock") }

      its(:length) { is_expected.to eq(1) }
    end

    context "with development dependencies" do
      let(:gemfile_content) do
        fixture("ruby", "gemfiles", "development_dependencies")
      end
      let(:lockfile_content) do
        fixture("ruby", "lockfiles", "development_dependencies.lock")
      end

      its(:length) { is_expected.to eq(2) }

      describe "the last dependency" do
        subject { dependencies.last }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("business") }
        its(:version) { is_expected.to eq("1.4.0") }
        its(:requirement) { is_expected.to eq("~> 1.4.0") }
        its(:groups) { is_expected.to eq(%i(development test)) }
      end
    end

    context "with a dependency that doesn't appear in the lockfile" do
      let(:gemfile_content) { fixture("ruby", "gemfiles", "platform_windows") }
      let(:lockfile_content) do
        fixture("ruby", "lockfiles", "platform_windows.lock")
      end

      its(:length) { is_expected.to eq(1) }
    end

    context "with a path-based dependency" do
      let(:files) { [gemfile, lockfile, gemspec] }
      let(:gemfile_content) { fixture("ruby", "gemfiles", "path_source") }
      let(:lockfile_content) do
        fixture("ruby", "lockfiles", "path_source.lock")
      end
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          name: "plugins/example/example.gemspec",
          content: fixture("ruby", "gemspecs", "example")
        )
      end

      its(:length) { is_expected.to eq(4) }
    end

    context "with a Gemfile that imports a gemspec" do
      let(:files) { [gemfile, lockfile, gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          name: "example.gemspec",
          content: gemspec_content
        )
      end
      let(:gemfile_content) { fixture("ruby", "gemfiles", "imports_gemspec") }
      let(:lockfile_content) do
        fixture("ruby", "lockfiles", "imports_gemspec.lock")
      end
      let(:gemspec_content) { fixture("ruby", "gemspecs", "small_example") }

      its(:length) { is_expected.to eq(2) }

      context "with a large gemspec" do
        let(:gemspec_content) { fixture("ruby", "gemspecs", "example") }
        let(:lockfile_content) do
          fixture("ruby", "lockfiles", "imports_gemspec_large.lock")
        end

        its(:length) { is_expected.to eq(13) }

        describe "the last dependency" do
          subject { dependencies.last }

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("gitlab") }
          its(:version) { is_expected.to eq("4.2.0") }
          its(:requirement) { is_expected.to eq("~> 4.1") }
          its(:groups) { is_expected.to eq(["runtime"]) }
        end

        context "that needs to be sanitized" do
          let(:gemspec_content) { fixture("ruby", "gemspecs", "with_require") }
          its(:length) { is_expected.to eq(13) }
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
  end
end
