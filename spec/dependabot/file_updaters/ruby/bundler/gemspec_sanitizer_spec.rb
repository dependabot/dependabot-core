# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/file_updaters/ruby/bundler/gemspec_sanitizer"

RSpec.describe Dependabot::FileUpdaters::Ruby::Bundler::GemspecSanitizer do
  let(:sanitizer) do
    described_class.new(replacement_version: replacement_version)
  end

  let(:replacement_version) { "1.5.0" }

  describe "#rewrite" do
    subject(:rewrite) { sanitizer.rewrite(content) }
    let(:content) { fixture("ruby", "gemspecs", "with_require") }

    context "with a requirement line" do
      let(:content) do
        %(require 'example/version'\nadd_dependency "require")
      end
      it { is_expected.to eq(%(\nadd_dependency "require")) }
    end

    context "with an assignment to a constant" do
      let(:content) { %(Spec.new { |s| s.version = Example::Version }) }
      it { is_expected.to eq(%(Spec.new { |s| s.version = "1.5.0" })) }

      context "that is fully capitalised" do
        let(:content) { %(Spec.new { |s| s.version = Example::VERSION }) }
        it { is_expected.to eq(%(Spec.new { |s| s.version = "1.5.0" })) }
      end
    end

    # rubocop:disable Lint/InterpolationCheck
    context "with an assignment to a string-interpolated constant" do
      let(:content) { %q(Spec.new { |s| s.version = "#{Example::Version}" }) }
      it { is_expected.to eq(%q(Spec.new { |s| s.version = "#{"1.5.0"}" })) }
    end
    # rubocop:enable Lint/InterpolationCheck
  end
end
