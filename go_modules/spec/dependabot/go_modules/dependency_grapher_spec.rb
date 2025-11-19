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

  let(:project_name) { "graphing_dependencies" }
  let(:repo_contents_path) { build_tmp_repo(project_name) }

  let(:parser) do
    Dependabot::FileParsers.for_package_manager("go_modules").new(
      dependency_files:,
      repo_contents_path: repo_contents_path,
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
            pkg:golang/github.com/fatih/color@v1.18.0
            pkg:golang/rsc.io/qr@v0.2.0
            pkg:golang/rsc.io/quote@v1.5.2
            pkg:golang/github.com/mattn/go-colorable@v0.1.14
            pkg:golang/github.com/mattn/go-isatty@v0.0.20
            pkg:golang/golang.org/x/sys@v0.36.0
            pkg:golang/golang.org/x/text@v0.0.0-20170915032832-14c0d48ead0c
            pkg:golang/rsc.io/sampler@v1.3.0
          )
        )

        # Direct dependencies
        color = resolved_dependencies["pkg:golang/github.com/fatih/color@v1.18.0"]
        expect(color.package_url).to eql("pkg:golang/github.com/fatih/color@v1.18.0")
        expect(color.direct).to be(true)
        expect(color.runtime).to be(true)

        qr = resolved_dependencies["pkg:golang/rsc.io/qr@v0.2.0"]
        expect(qr.package_url).to eql("pkg:golang/rsc.io/qr@v0.2.0")
        expect(qr.direct).to be(true)
        expect(qr.runtime).to be(true)

        quote = resolved_dependencies["pkg:golang/rsc.io/quote@v1.5.2"]
        expect(quote.package_url).to eql("pkg:golang/rsc.io/quote@v1.5.2")
        expect(quote.direct).to be(true)
        expect(quote.runtime).to be(true)

        # Spot check indirect dependencies
        colorable = resolved_dependencies["pkg:golang/github.com/mattn/go-colorable@v0.1.14"]
        expect(colorable.package_url).to eql("pkg:golang/github.com/mattn/go-colorable@v0.1.14")
        expect(colorable.direct).to be(false)
        expect(colorable.runtime).to be(true)

        isatty = resolved_dependencies["pkg:golang/github.com/mattn/go-isatty@v0.0.20"]
        expect(isatty.package_url).to eql("pkg:golang/github.com/mattn/go-isatty@v0.0.20")
        expect(isatty.direct).to be(false)
        expect(isatty.runtime).to be(true)
      end

      # We have disabled fetching of relationships due to a problem with `go mod graph` and our handling of
      # `replace` directives causing some projects to choke on this step.
      describe "assigns child dependencies using go mod graph" do
        let(:dependency_graph_expectations) do
          [
            {
              name: "pkg:golang/github.com/fatih/color@v1.18.0",
              depends_on: [
                "pkg:golang/github.com/mattn/go-colorable@v0.1.14",
                "pkg:golang/github.com/mattn/go-isatty@v0.0.20",
                "pkg:golang/golang.org/x/sys@v0.36.0"
              ]
            },
            {
              name: "pkg:golang/github.com/mattn/go-colorable@v0.1.14",
              depends_on: [
                "pkg:golang/github.com/mattn/go-isatty@v0.0.20",
                "pkg:golang/golang.org/x/sys@v0.36.0"
              ]
            },
            {
              name: "pkg:golang/github.com/mattn/go-isatty@v0.0.20",
              depends_on: [
                "pkg:golang/golang.org/x/sys@v0.36.0"
              ]
            },
            {
              name: "pkg:golang/rsc.io/quote@v1.5.2",
              depends_on: [
                "pkg:golang/rsc.io/sampler@v1.3.0"
              ]
            },
            {
              name: "pkg:golang/rsc.io/sampler@v1.3.0",
              depends_on: [
                "pkg:golang/golang.org/x/text@v0.0.0-20170915032832-14c0d48ead0c"
              ]
            },
            {
              name: "pkg:golang/golang.org/x/text@v0.0.0-20170915032832-14c0d48ead0c",
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

      describe "when go mod graph includes pruned modules" do
        let(:graph_output_with_pruned) do
          <<~GRAPH
            github.com/dependabot/core-test github.com/fatih/color@v1.18.0
            github.com/fatih/color github.com/mattn/go-colorable@v0.1.14
            github.com/fatih/color github.com/mattn/go-isatty@v0.0.20
            github.com/fatih/color golang.org/x/sys@v0.36.0
            github.com/fatih/color golang.org/x/tools@v0.17.0
            github.com/mattn/go-colorable golang.org/x/sys@v0.36.0
            github.com/mattn/go-colorable golang.org/x/tools@v0.17.0
            github.com/mattn/go-isatty golang.org/x/sys@v0.36.0
            rsc.io/quote rsc.io/sampler@v1.3.0
            rsc.io/sampler golang.org/x/text@v0.0.0-20170915032832-14c0d48ead0c
            golang.org/x/text go@1.24.0
          GRAPH
        end

        it "filters out pruned subdependencies" do
          allow(parser).to receive(:run_in_parsed_context).and_call_original
          allow(parser).to receive(:run_in_parsed_context).with("go mod graph").and_return(graph_output_with_pruned)

          resolved = grapher.resolved_dependencies
          color = resolved.fetch("pkg:golang/github.com/fatih/color@v1.18.0")
          expect(color.dependencies).to include(
            "pkg:golang/github.com/mattn/go-colorable@v0.1.14",
            "pkg:golang/github.com/mattn/go-isatty@v0.0.20",
            "pkg:golang/golang.org/x/sys@v0.36.0"
          )
          expect(color.dependencies).not_to include("pkg:golang/golang.org/x/tools@v0.17.0")

          text_pkg = resolved.fetch("pkg:golang/golang.org/x/text@v0.0.0-20170915032832-14c0d48ead0c")
          expect(text_pkg.dependencies).not_to include("pkg:golang/go@1.24.0")

          all_children = resolved.values.flat_map(&:dependencies)
          expect(all_children).not_to include("pkg:golang/golang.org/x/tools@v0.17.0")
          expect(all_children).not_to include("pkg:golang/go@1.24.0")
        end
      end
    end
  end
end
