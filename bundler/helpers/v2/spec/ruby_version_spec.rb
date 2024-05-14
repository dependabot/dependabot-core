# typed: false
# frozen_string_literal: true

require "native_spec_helper"
require "shared_contexts"

RSpec.describe BundlerDefinitionRubyVersionPatch do
  include_context "when in a temporary bundler directory"
  include_context "when stub rubygems compact index"

  let(:project_name) { "ruby_version_implied" }
  before do
    @ui = Bundler.ui
    Bundler.ui = Bundler::UI::Silent.new
  end
  after { Bundler.ui = @ui }

  it "updates to the most recent version" do
    in_tmp_folder do
      File.delete(".ruby-version")
      definition = Bundler::Definition.build("Gemfile", "Gemfile.lock", gems: ["statesman"])
      definition.resolve_remotely!
      specs = definition.resolve["statesman"]
      expect(specs.size).to eq(1)
      spec = specs.first
      expect(spec.version).to eq("7.2.0")
    end
  end

  it "doesn't update to a version that is not compatible with the Ruby version implied by .ruby-version" do
    in_tmp_folder do
      definition = Bundler::Definition.build("Gemfile", "Gemfile.lock", gems: ["statesman"])
      definition.resolve_remotely!
      specs = definition.resolve["statesman"]
      expect(specs.size).to eq(1)
      spec = specs.first
      expect(spec.version).to eq("2.0.1")
    end
  end
end
