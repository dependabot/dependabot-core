# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/file_updater/go_mod_graph"

RSpec.describe Dependabot::GoModules::FileUpdater::GoModGraph do
  describe ".capture" do
    context "when go mod graph succeeds" do
      before do
        graph_output = <<~GRAPH
          github.com/test/app github.com/onsi/gomega@v1.39.0
          github.com/test/app google.golang.org/grpc@v1.81.1
          google.golang.org/grpc@v1.81.1 gonum.org/v1/gonum@v0.17.0
          github.com/onsi/gomega@v1.39.0 golang.org/x/net@v0.43.0
        GRAPH

        allow(Open3).to receive(:capture3)
          .with("go mod graph")
          .and_return([graph_output, "", instance_double(Process::Status, success?: true)])
      end

      it "parses module entries from the graph output" do
        graph = described_class.capture
        expect(graph.modules).to include("google.golang.org/grpc@v1.81.1")
        expect(graph.modules).to include("gonum.org/v1/gonum@v0.17.0")
        expect(graph.modules).to include("github.com/onsi/gomega@v1.39.0")
      end

      it "is not empty" do
        expect(described_class.capture).not_to be_empty
      end
    end

    context "when go mod graph fails" do
      before do
        allow(Open3).to receive(:capture3)
          .with("go mod graph")
          .and_return(["", "error", instance_double(Process::Status, success?: false)])
      end

      it "returns an empty graph" do
        expect(described_class.capture).to be_empty
      end
    end
  end

  describe "#changed_modules" do
    it "detects modules with changed versions" do
      before_graph = described_class.new(
        modules: Set[
          "github.com/onsi/gomega@v1.39.0",
          "google.golang.org/grpc@v1.81.1",
          "gonum.org/v1/gonum@v0.17.0"
        ]
      )

      after_graph = described_class.new(
        modules: Set[
          "github.com/onsi/gomega@v1.40.0",
          "google.golang.org/grpc@v1.81.1",
          "gonum.org/v1/gonum@v0.17.0"
        ]
      )

      changed = before_graph.changed_modules(after_graph)
      expect(changed).to include("github.com/onsi/gomega")
      expect(changed).not_to include("google.golang.org/grpc")
      expect(changed).not_to include("gonum.org/v1/gonum")
    end

    it "detects added modules" do
      before_graph = described_class.new(
        modules: Set["github.com/onsi/gomega@v1.39.0"]
      )

      after_graph = described_class.new(
        modules: Set[
          "github.com/onsi/gomega@v1.39.0",
          "github.com/kr/pretty@v0.3.1"
        ]
      )

      changed = before_graph.changed_modules(after_graph)
      expect(changed).to include("github.com/kr/pretty")
      expect(changed).not_to include("github.com/onsi/gomega")
    end

    it "detects removed modules" do
      before_graph = described_class.new(
        modules: Set[
          "github.com/onsi/gomega@v1.39.0",
          "github.com/old/dep@v1.0.0"
        ]
      )

      after_graph = described_class.new(
        modules: Set["github.com/onsi/gomega@v1.39.0"]
      )

      changed = before_graph.changed_modules(after_graph)
      expect(changed).to include("github.com/old/dep")
      expect(changed).not_to include("github.com/onsi/gomega")
    end

    it "returns empty set when graphs are identical" do
      graph = described_class.new(
        modules: Set[
          "github.com/onsi/gomega@v1.39.0",
          "gonum.org/v1/gonum@v0.17.0"
        ]
      )

      expect(graph.changed_modules(graph)).to be_empty
    end
  end
end
