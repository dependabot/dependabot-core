# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bundler"
require "dependabot/dependency_graphers"

# TODO: Implement a concrete Bundler class
RSpec.describe "Dependabot::DependencyGraphers::Generic" do
  context "with a bundler project" do
    subject(:grapher) do
      Dependabot::DependencyGraphers.for_package_manager("bundler").new(
        file_parser: parser
      )
    end

    let(:parser) do
      Dependabot::FileParsers.for_package_manager("bundler").new(
        dependency_files:,
        repo_contents_path: nil,
        source: source,
        credentials: [],
        reject_external_code: false
      )
    end

    let(:source) do
      Dependabot::Source.new(
        provider: "github",
        repo: "dependabot-fixtures/dependabot-test-ruby-package",
        directory: "/",
        branch: "main"
      )
    end

    let(:dependencies) { parser.parse }

    before { grapher.prepare! }

    # NOTE: This documents existing behaviour where Gemfile PURLs do not include a resolved version
    #
    # Package URLs deal in resolved versions, so for a Gemfile only project we only have a range
    # which cannot currently be submitted to the Dependency Submission API.
    #
    # This is working as intended, but when we implement a concrete Bundler grapher we will want
    # to execute a `bundle install` to resolve the file at runtime so we can submit the resolved
    # dependencies.
    context "with a Gemfile only" do
      let(:gemfile) do
        bundler_project_dependency_file("subdependency", filename: "Gemfile")
      end

      let(:dependency_files) do
        [gemfile]
      end

      it "specifies the Gemfile as the relevant dependency file" do
        expect(grapher.relevant_dependency_file).to eql(gemfile)
      end

      it "correctly serializes the resolved dependencies" do
        expect(grapher.resolved_dependencies.count).to be(1)

        ibandit = grapher.resolved_dependencies["ibandit"]
        expect(ibandit[:package_url]).to eql("pkg:gem/ibandit")
        expect(ibandit[:relationship]).to eql("direct")
        expect(ibandit[:scope]).to eql("runtime")
        expect(ibandit[:dependencies]).to be_empty
      end
    end

    context "with a Gemfile and Gemfile.lock" do
      let(:gemfile) do
        bundler_project_dependency_file("subdependency", filename: "Gemfile")
      end

      let(:gemfile_lock) do
        bundler_project_dependency_file("subdependency", filename: "Gemfile.lock")
      end

      let(:dependency_files) do
        [gemfile, gemfile_lock]
      end

      it "specifies the Gemfile.lock as the relevant dependency file" do
        expect(grapher.relevant_dependency_file).to eql(gemfile_lock)
      end

      it "correctly serializes the resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies.count).to be(2)

        expect(resolved_dependencies.keys).to eql(%w(ibandit i18n))

        ibandit = resolved_dependencies["ibandit"]
        expect(ibandit[:package_url]).to eql("pkg:gem/ibandit@0.7.0")
        expect(ibandit[:relationship]).to eql("direct")
        expect(ibandit[:scope]).to eql("runtime")
        expect(ibandit[:dependencies]).to be_empty # NYI: We don't set any subdependencies yet, this should contain i18n

        i18n = resolved_dependencies["i18n"]
        expect(i18n[:package_url]).to eql("pkg:gem/i18n@0.7.0.beta1")
        expect(i18n[:relationship]).to eql("indirect")
        expect(i18n[:scope]).to eql("runtime")
        expect(i18n[:dependencies]).to be_empty
      end
    end
  end
end
