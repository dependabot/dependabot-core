# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/update_checker/pip_version_resolver/marker_evaluator"

RSpec.describe Dependabot::Python::UpdateChecker::PipVersionResolver::MarkerEvaluator do
  subject(:marker_evaluator) { described_class.new }

  describe "#split_requirement_and_marker" do
    it "returns the requirement unchanged when no marker separator exists" do
      requirement, marker = marker_evaluator.split_requirement_and_marker("urllib3 (<1.27,>=1.25.4)")

      expect(requirement).to eq("urllib3 (<1.27,>=1.25.4)")
      expect(marker).to be_nil
    end

    it "ignores semicolons inside quoted marker values" do
      requirement, marker = marker_evaluator.split_requirement_and_marker(
        "urllib3 (<1.27,>=1.25.4) ; extra == 'crt;gpu' and python_version >= '3.10'"
      )

      expect(requirement).to eq("urllib3 (<1.27,>=1.25.4)")
      expect(marker).to eq("extra == 'crt;gpu' and python_version >= '3.10'")
    end
  end

  describe "#marker_satisfied?" do
    let(:python_version) { "3.11.0" }

    it "applies unary not only to the following term before evaluating and" do
      marker = "not python_version >= '3.0' and python_version < '3.0'"

      expect(marker_evaluator.marker_satisfied?(marker: marker, python_version: python_version)).to be(false)
    end

    it "evaluates unary not with lower-precedence or expressions correctly" do
      marker = "not python_version < '3.0' or python_version >= '3.0'"

      expect(marker_evaluator.marker_satisfied?(marker: marker, python_version: python_version)).to be(true)
    end

    it "does not treat non-python unary-not terms as satisfying python checks in or branches" do
      marker = "python_version < '3.0' or not extra == 'crt'"

      expect(marker_evaluator.marker_satisfied?(marker: marker, python_version: python_version)).to be(false)
    end
  end
end
