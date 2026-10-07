# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bazel/file_fetcher/path_converter"

RSpec.describe Dependabot::Bazel::FileFetcher::PathConverter do
  describe ".label_to_path" do
    context "with absolute workspace labels" do
      it "converts //pkg:file.bzl to pkg/file.bzl" do
        expect(described_class.label_to_path("//foo/bar:baz.bzl")).to eq("foo/bar/baz.bzl")
      end

      it "converts //pkg:subdir/file.bzl with nested target" do
        expect(described_class.label_to_path("//tools:build/defs.bzl")).to eq("tools/build/defs.bzl")
      end

      it "converts label without colon separator" do
        expect(described_class.label_to_path("//foo/bar")).to eq("foo/bar")
      end
    end

    context "with relative labels" do
      it "converts :file.bzl without context_dir" do
        expect(described_class.label_to_path(":helper.bzl")).to eq("helper.bzl")
      end

      it "converts :file.bzl with context_dir" do
        expect(described_class.label_to_path(":helper.bzl", context_dir: "lib/tools")).to eq("lib/tools/helper.bzl")
      end

      it "converts :file.bzl with dot context_dir" do
        expect(described_class.label_to_path(":helper.bzl", context_dir: ".")).to eq("helper.bzl")
      end
    end

    context "with external repo labels" do
      it "strips the @repo// prefix" do
        expect(described_class.label_to_path("@rules_go//go:def.bzl")).to eq("go/def.bzl")
      end
    end
  end

  describe ".should_filter_path?" do
    it "returns true for http URLs" do
      expect(described_class.should_filter_path?("http://example.com")).to be(true)
    end

    it "returns true for https URLs" do
      expect(described_class.should_filter_path?("https://example.com")).to be(true)
    end

    it "returns true for absolute filesystem paths" do
      expect(described_class.should_filter_path?("/usr/local/bin")).to be(true)
    end

    it "returns true for external repo references" do
      expect(described_class.should_filter_path?("@rules_go//go")).to be(true)
    end

    it "returns false for relative paths" do
      expect(described_class.should_filter_path?("foo/bar.bzl")).to be(false)
    end
  end

  describe ".normalize_path" do
    it "removes leading ./" do
      expect(described_class.normalize_path("./foo/bar.bzl")).to eq("foo/bar.bzl")
    end

    it "leaves paths without leading ./ unchanged" do
      expect(described_class.normalize_path("foo/bar.bzl")).to eq("foo/bar.bzl")
    end
  end
end
