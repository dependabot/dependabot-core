require "spec_helper"
require "./lib/python_helpers"

RSpec.describe PythonHelpers do
  describe ".requirements parsing" do
    subject { described_class.new }

    context "when requirements if empty" do
      it "returns empty list" do
        expect(PythonHelpers.requirements_parse("")).to eq([])
      end
    end

    context "when requirements is invalid" do
      it "returns empty list" do
        expect(PythonHelpers.requirements_parse("-f a")).to eq([])
      end
    end

    context "when requirements has valid entries" do
      it "returns list with name version pairs" do
        expect(PythonHelpers.requirements_parse("a==2.0\nb==3.1.2")).
          to eq([["a", "2.0"], ["b", "3.1.2"]])
      end
    end
  end
end
