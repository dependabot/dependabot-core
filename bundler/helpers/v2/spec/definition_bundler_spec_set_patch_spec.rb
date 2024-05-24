# typed: false
# frozen_string_literal: true

require "native_spec_helper"
require "shared_contexts"

RSpec.describe Bundler::LazySpecification do
  let(:specification) do
    spec = Bundler::LazySpecification.new("example", "1.1.0", nil)
    spec.extend(BundlerSpecSetPatch)
    spec
  end

  describe "#default_gem?" do
    let(:default_spec_dir) { "/mocked/default/spec/dir" }
    before do
      allow(Gem).to receive(:default_specifications_dir).and_return(default_spec_dir)
    end

    context "when the gem is a default gem" do
      it "returns true if the loaded_from path is in the default specifications directory" do
        specification.loaded_from = File.join(default_spec_dir, "example-1.1.0.gemspec")
        expect(specification.default_gem?).to be true
      end
    end

    context "when loaded_from is nil" do
      it "returns false" do
        specification.loaded_from = nil
        expect(specification.default_gem?).to be false
      end
    end

    context "when the gem is not a default gem" do
      it "returns false if the loaded_from path is not in the default specifications directory" do
        non_default_dir = "/path/to/non/default/directory"
        specification.loaded_from = File.join(non_default_dir, "example-1.1.0.gemspec")
        expect(specification.default_gem?).to be false
      end
    end
  end
end
