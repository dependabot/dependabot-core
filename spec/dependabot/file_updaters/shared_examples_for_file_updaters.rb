# frozen_string_literal: true

require "spec_helper"
require "dependabot/file_updaters/base"

RSpec.shared_examples "a dependency file updater" do
  describe "the class" do
    subject { described_class }
    let(:base_class) { Dependabot::FileUpdaters::Base }

    its(:updated_files_regex) { is_expected.to be_an_instance_of(Array) }

    def recent_ancestors
      ancestors = described_class.ancestors.take_while { |a| a != base_class }
      [described_class] + ancestors
    end

    def own_public_methods(include_ancestor_methods)
      methods = (recent_ancestors + [described_class]).
        map { |cls| cls.public_instance_methods(include_ancestor_methods) }.
        flatten.
        uniq
    end

    def own_private_methods(include_ancestor_methods)
      methods = (recent_ancestors + [described_class]).
        map { |cls| cls.private_instance_methods(include_ancestor_methods) }.
        flatten
    end

    it "inherits from the base class" do
      expect(described_class.ancestors).to include(base_class)
    end

    it "implements updated_dependency_files" do
      expect(own_public_methods(false)).to include(:updated_dependency_files)
    end

    it "implements check_required_files" do
      expect(own_private_methods(false)).to include(:check_required_files)
    end

    it "doesn't define any additional public instance methods" do
      expect(own_public_methods(true)).
        to match_array(base_class.public_instance_methods(true))
    end
  end
end
