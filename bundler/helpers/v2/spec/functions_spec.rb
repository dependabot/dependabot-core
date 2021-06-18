# frozen_string_literal: true

require "native_spec_helper"
require "shared_contexts"

RSpec.describe Functions do
  include_context "in a temporary bundler directory"

  describe "#jfrog_source" do
    let(:project_name) { "jfrog_source" }

    it "returns the jfrog source" do
      in_tmp_folder do
        jfrog_source = Functions.jfrog_source(
          dir: tmp_path,
          gemfile_name: "Gemfile",
          credentials: {}
        )

        expect(jfrog_source).to eq("test.jfrog.io")
      end
    end
  end
end
