# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/go_work_parser"

RSpec.describe Dependabot::GoModules::GoWorkParser do
  describe ".use_paths" do
    subject(:paths) { described_class.use_paths(content) }

    context "with a multi-line use block containing root and subdirs" do
      let(:content) do
        <<~GOWORK
          go 1.21

          use (
            .
            ./libs
            ./services
          )
        GOWORK
      end

      it { is_expected.to eq([".", "libs", "services"]) }
    end

    context "with a single-line use for root module (use .)" do
      let(:content) { "use ." }

      it { is_expected.to eq(["."]) }
    end

    context "with a single-line use for a subdirectory (use ./sub/dir)" do
      let(:content) { "use ./sub/dir" }

      it { is_expected.to eq(["sub/dir"]) }
    end

    context "with a single-line use directive with a trailing inline comment" do
      let(:content) { "use ./sub/dir // some comment" }

      it { is_expected.to eq(["sub/dir"]) }
    end

    context "with inline comments on use lines" do
      let(:content) do
        <<~GOWORK
          use (
            ./libs // some comment
            ./services
          )
        GOWORK
      end

      it { is_expected.to eq(["libs", "services"]) }
    end

    context "with mixed block and single-line use directives" do
      let(:content) do
        <<~GOWORK
          go 1.21
          use (
            ./api
          )
          use ./worker
        GOWORK
      end

      it { is_expected.to eq(["api", "worker"]) }
    end

    context "with duplicate paths" do
      let(:content) do
        <<~GOWORK
          use (
            ./api
            ./api
          )
        GOWORK
      end

      it "deduplicates" do
        is_expected.to eq(["api"])
      end
    end

    context "with empty content" do
      let(:content) { "" }

      it { is_expected.to eq([]) }
    end

    context "with whitespace-only content" do
      let(:content) { "   \n\n   " }

      it { is_expected.to eq([]) }
    end

    context "with a go.work containing toolchain and godebug directives" do
      let(:content) do
        <<~GOWORK
          go 1.21
          toolchain go1.21.0
          godebug default=go1.21

          use (
            .
            ./cmd
          )
        GOWORK
      end

      it "ignores non-use directives" do
        is_expected.to eq([".", "cmd"])
      end
    end
  end
end
