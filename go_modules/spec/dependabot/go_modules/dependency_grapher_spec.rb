# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules"

RSpec.describe Dependabot::GoModules::DependencyGrapher do
  subject(:grapher) do
    Dependabot::DependencyGraphers.for_package_manager("go_modules").new(
      file_parser: parser
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

  let(:dependency_files) { [go_mod] }

  after do
    # Reset the environment variable after each test to avoid side effects
    ENV.delete("GOENV")
    ENV.delete("GOPROXY")
    ENV.delete("GOPRIVATE")
  end

  context "with a simple project" do
    let(:go_mod) do
      Dependabot::DependencyFile.new(
        name: "go.mod",
        content: fixture("projects", "graphing_dependencies", "go.mod"),
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

        expect(resolved_dependencies.count).to be(8)

        expect(resolved_dependencies.keys).to eql(
          %w(
            github.com/fatih/color
            rsc.io/qr
            rsc.io/quote
            github.com/mattn/go-colorable
            github.com/mattn/go-isatty
            golang.org/x/sys
            golang.org/x/text
            rsc.io/sampler
          )
        )

        # Direct dependencies
        color = resolved_dependencies["github.com/fatih/color"]
        expect(color.package_url).to eql("pkg:golang/github.com/fatih/color@v1.18.0")
        expect(color.direct).to be(true)
        expect(color.runtime).to be(true)

        qr = resolved_dependencies["rsc.io/qr"]
        expect(qr.package_url).to eql("pkg:golang/rsc.io/qr@v0.2.0")
        expect(qr.direct).to be(true)
        expect(qr.runtime).to be(true)

        quote = resolved_dependencies["rsc.io/quote"]
        expect(quote.package_url).to eql("pkg:golang/rsc.io/quote@v1.5.2")
        expect(quote.direct).to be(true)
        expect(quote.runtime).to be(true)

        # Spot check indirect dependencies
        colorable = resolved_dependencies["github.com/mattn/go-colorable"]
        expect(colorable.package_url).to eql("pkg:golang/github.com/mattn/go-colorable@v0.1.14")
        expect(colorable.direct).to be(false)
        expect(colorable.runtime).to be(true)

        isatty = resolved_dependencies["github.com/mattn/go-isatty"]
        expect(isatty.package_url).to eql("pkg:golang/github.com/mattn/go-isatty@v0.0.20")
        expect(isatty.direct).to be(false)
        expect(isatty.runtime).to be(true)
      end

      describe "assigns child dependencies using go mod graph" do
        let(:dependency_graph_expectations) do
          [
            {
              name: "github.com/fatih/color",
              depends_on: [
                "pkg:golang/github.com/mattn/go-colorable@v0.1.13",
                "pkg:golang/github.com/mattn/go-isatty@v0.0.20",
                "pkg:golang/golang.org/x/sys@v0.25.0"
              ]
            },
            {
              name: "github.com/mattn/go-colorable",
              depends_on: [
                "pkg:golang/github.com/mattn/go-isatty@v0.0.20",
                "pkg:golang/golang.org/x/sys@v0.29.0"
              ]
            },
            {
              name: "github.com/mattn/go-isatty",
              depends_on: [
                "pkg:golang/golang.org/x/sys@v0.6.0"
              ]
            },
            {
              name: "rsc.io/quote",
              depends_on: [
                "pkg:golang/rsc.io/sampler@v1.3.0"
              ]
            },
            {
              name: "rsc.io/sampler",
              depends_on: [
                "pkg:golang/golang.org/x/text@v0.0.0-20170915032832-14c0d48ead0c"
              ]
            },
            {
              name: "golang.org/x/text",
              depends_on: []
            }
          ]
        end

        it "correctly assigns depends_on for each package" do
          dependency_graph_expectations.each do |expectation|
            dependency = grapher.resolved_dependencies.fetch(expectation[:name], nil)
            expect(dependency).not_to be_nil

            expect(dependency.dependencies).to eql(expectation[:depends_on])
          end
        end
      end
    end
  end
end
