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

  describe "#git_specs" do
    let(:project_name) { "git_source" }
    subject(:git_specs) do
      in_tmp_folder do
        Functions.git_specs(
          dir: tmp_path,
          gemfile_name: "Gemfile",
          credentials: {}
        )
      end
    end

    def expect_specs(count)
      expect(git_specs.size).to eq(count)
      git_specs.each do |gs|
        uri = URI.parse(gs[:auth_uri])
        expect(uri.scheme).to(satisfy { |s| %w(http https).include?(s) })
      end
    end

    it "returns git specs" do
      expect_specs(4)
    end

    context "with github shorthand" do
      let(:project_name) { "github_source" }

      it "returns git specs" do
        expect_specs(1)
      end
    end
  end
end
