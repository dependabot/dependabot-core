# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules"

RSpec.describe Dependabot::GoModules::DependencyGrapher do
  subject(:grapher) do
    Dependabot::DependencyGraphers.for_package_manager("go_modules").new(
      dependency_files:,
      dependencies:
    )
  end

  let(:parser) do
    Dependabot::FileParsers.for_package_manager("go_modules").new(
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
      repo: "dependabot/dependabot-cli",
      directory: "/",
      branch: "main"
    )
  end

  let(:dependencies) { parser.parse }
  let(:dependency_files) { [go_mod] }

  after do
    # Reset the environment variable after each test to avoid side effects
    ENV.delete("GOENV")
    ENV.delete("GOPROXY")
    ENV.delete("GOPRIVATE")
  end

  context "when the go.mod is unexpectedly missing from dependency_files" do
    # This scenario is very unlikely, it would most likely result from
    # programmer error where the set of files passed in is malformed.
    subject(:grapher) do
      Dependabot::DependencyGraphers.for_package_manager("go_modules").new(
        dependency_files: [],
        dependencies:
      )
    end

    let(:go_mod) do
      Dependabot::DependencyFile.new(
        name: "go.mod",
        content: fixture("go_mods", "go.mod"),
        directory: "/"
      )
    end

    describe "#relevant_dependency_file" do
      it "throws an exception" do
        expect { grapher.relevant_dependency_file }.to raise_error(Dependabot::DependabotError, /No go.mod present/)
      end
    end
  end

  context "with a simple project" do
    let(:go_mod) do
      Dependabot::DependencyFile.new(
        name: "go.mod",
        content: fixture("go_mods", "go.mod"),
        directory: "/"
      )
    end

    describe "#relevant_dependency_file" do
      it "specifies the go_mod as the relevant dependency file" do
        expect(grapher.relevant_dependency_file).to eql(go_mod)
      end
    end

    describe "#resolved_dependencies" do
      it "correctly serializes the resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies.count).to be(4)

        expect(resolved_dependencies.keys).to eql(
          %w(
            github.com/fatih/Color
            github.com/mattn/go-colorable
            github.com/mattn/go-isatty
            rsc.io/quote
          )
        ) # rsc.io/qr is absent due to the replace directive, this is working as intended.

        color = resolved_dependencies["github.com/fatih/Color"]
        expect(color[:package_url]).to eql("pkg:golang/github.com/fatih/Color@v1.7.0")
        expect(color[:relationship]).to eql("direct")
        expect(color[:scope]).to eql("runtime")
        expect(color[:dependencies]).to be_empty # NYI: We don't set any subdependencies yet

        colorable = resolved_dependencies["github.com/mattn/go-colorable"]
        expect(colorable[:package_url]).to eql("pkg:golang/github.com/mattn/go-colorable@v0.0.9")
        expect(colorable[:relationship]).to eql("indirect")
        expect(colorable[:scope]).to eql("runtime")
        expect(colorable[:dependencies]).to be_empty

        quote = resolved_dependencies["rsc.io/quote"]
        expect(quote[:package_url]).to eql("pkg:golang/rsc.io/quote@v1.4.0")
        expect(quote[:relationship]).to eql("direct")
        expect(quote[:scope]).to eql("runtime")
        expect(quote[:dependencies]).to be_empty
      end
    end
  end
end
