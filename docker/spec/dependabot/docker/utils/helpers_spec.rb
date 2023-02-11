# # frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/docker/utils/helpers"
require "spec_helper"

RSpec.describe Dependabot::Docker::Utils.likely_helm_chart? do
  describe "#likely_helm_chart?" do
    matching_filenames = [
      "other-values.yml",
      "other-values.yaml",
      "other_values.yml",
      "other_values.yaml",
      "values.yml",
      "values.yaml",
      "values-other.yml",
      "values-other.yaml",
      "values_other.yml",
      "values_other.yaml",
      "values2.yml",
      "values2.yaml"
    ]
    matching_filenames.each do |fname|
      it "should return `true` for matching value '#{fname}'" do
        fake_file = Dependabot::DependencyFile.new(
          name: fname,
          content: "fake content"
        )
        expect(self.likely_helm_chart?(fake_file)).to be true
      end
    end
  end
end
