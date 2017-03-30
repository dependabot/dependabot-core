# frozen_string_literal: true
require "spec_helper"
require "./lib/python_helpers"

RSpec.describe PythonHelpers do
  describe ".parse_requirements" do
    subject { described_class.new }

    context "when requirements if empty" do
      it "returns empty list" do
        expect(PythonHelpers.parse_requirements("")).to eq([])
      end
    end

    context "when requirements is invalid" do
      it "returns empty list" do
        expect(PythonHelpers.parse_requirements("-f a")).to eq([])
      end
    end

    context "when requirements has valid entries" do
      it "returns list with name version pairs" do
        expect(PythonHelpers.parse_requirements("a==2.0\nb==3.1.2")).
          to eq([["a", "2.0"], ["b", "3.1.2"]])
      end
    end
  end
end
