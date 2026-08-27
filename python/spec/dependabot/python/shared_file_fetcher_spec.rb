# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/shared_file_fetcher"

RSpec.describe Dependabot::Python::SharedFileFetcher do
  describe "CHILD_REQUIREMENT_REGEX" do
    {
      "-r base.txt" => "base.txt",
      "-rbase.txt" => "base.txt",
      "-r base.in" => "base.in",
      "-r ../base.txt" => "../base.txt",
      "--requirement base.txt" => "base.txt",
      "--requirement  base.txt" => "base.txt",
      "--requirement=base.txt" => "base.txt",
      "--requirement base.in" => "base.in",
      "--requirement ../base.txt" => "../base.txt"
    }.each do |line, path|
      it "captures #{path.inspect} from #{line.inspect}" do
        expect(described_class::CHILD_REQUIREMENT_REGEX.match(line)[:path]).to eq(path)
      end
    end

    [
      "--requirementbase.txt",
      "--requirements-file base.txt",
      "-r base.cfg",
      "  -r base.txt",
      "# -r base.txt",
      "requests==2.4.1"
    ].each do |line|
      it "does not match #{line.inspect}" do
        expect(described_class::CHILD_REQUIREMENT_REGEX).not_to match(line)
      end
    end
  end

  describe "CONSTRAINT_REGEX" do
    {
      "-c constraints.txt" => "constraints.txt",
      "-cconstraints.txt" => "constraints.txt",
      "-c constraints.in" => "constraints.in",
      "-c ../constraints.txt" => "../constraints.txt",
      "--constraint constraints.txt" => "constraints.txt",
      "--constraint  constraints.txt" => "constraints.txt",
      "--constraint=constraints.txt" => "constraints.txt",
      "--constraint constraints.in" => "constraints.in",
      "--constraint ../constraints.txt" => "../constraints.txt"
    }.each do |line, path|
      it "captures #{path.inspect} from #{line.inspect}" do
        expect(described_class::CONSTRAINT_REGEX.match(line)[:path]).to eq(path)
      end
    end

    [
      "--constraintconstraints.txt",
      "--constraints constraints.txt",
      "-c constraints.cfg",
      "  -c constraints.txt",
      "# -c constraints.txt",
      "requests==2.4.1"
    ].each do |line|
      it "does not match #{line.inspect}" do
        expect(described_class::CONSTRAINT_REGEX).not_to match(line)
      end
    end
  end

  describe "EDITABLE_REGEX" do
    [
      "-e .",
      "-e  .",
      "--editable .",
      "--editable  .",
      "--editable=."
    ].each do |line|
      it "matches #{line.inspect}" do
        expect(described_class::EDITABLE_REGEX).to match(line)
      end
    end

    [
      "-e.",
      "--editable.",
      "--editable-package .",
      "  -e .",
      "# -e .",
      "requests==2.4.1"
    ].each do |line|
      it "does not match #{line.inspect}" do
        expect(described_class::EDITABLE_REGEX).not_to match(line)
      end
    end
  end

  describe "EDITABLE_PATH_REGEX" do
    {
      "-e ." => ".",
      "-e ./my" => "./my",
      '-e "./my"' => "./my",
      "-e './my'" => "./my",
      "-e file:." => ".",
      "--editable ./my" => "./my",
      "--editable  ./my" => "./my",
      "--editable=./my" => "./my",
      '--editable "./my"' => "./my",
      "--editable file:." => "."
    }.each do |line, path|
      it "captures #{path.inspect} from #{line.inspect}" do
        expect(described_class::EDITABLE_PATH_REGEX.match(line)[:path]).to eq(path)
      end
    end

    [
      "--editable-package .",
      "  -e .",
      "./my",
      "requests==2.4.1"
    ].each do |line|
      it "does not match #{line.inspect}" do
        expect(described_class::EDITABLE_PATH_REGEX).not_to match(line)
      end
    end
  end
end
