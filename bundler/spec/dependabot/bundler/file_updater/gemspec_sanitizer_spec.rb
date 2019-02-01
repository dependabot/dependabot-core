# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/bundler/file_updater/gemspec_sanitizer"

RSpec.describe Dependabot::Bundler::FileUpdater::GemspecSanitizer do
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

      it do
        is_expected.to eq(
          "begin\n"\
          "require 'example/version'\n"\
          "rescue LoadError\n"\
          "end\n"\
          'add_dependency "require"'
        )
      end
    end

    context "with a require_relative line" do
      let(:content) do
        %(require_relative 'example/version'\nadd_dependency "require")
      end

      it do
        is_expected.to eq(
          "begin\n"\
          "require_relative 'example/version'\n"\
          "rescue LoadError\n"\
          "end\n"\
          'add_dependency "require"'
        )
      end
    end

    context "with a File.read line" do
      let(:content) do
        %(version = File.read("something").strip\ncode = "require")
      end
      it { is_expected.to eq(%(version = "text".strip\ncode = "require")) }

      context "that uses File.readlines" do
        let(:content) do
          %(version = File.readlines("something").grep(/\S+/)\ncode = "require")
        end
        it do
          is_expected.to eq(%(version = ["text"].grep(/\S+/)\ncode = "require"))
        end
      end
    end

    context "with a Find.find line" do
      let(:content) do
        %(Find.find("lib", "whatever")\ncode = "require")
      end
      it { is_expected.to eq(%(Find.find()\ncode = "require")) }
    end

    context "with an unnecessary assignment" do
      let(:content) do
        %(Spec.new { |s| s.version = "0.1.0"\n s.post_install_message = "a" })
      end
      it do
        is_expected.to eq(%(Spec.new { |s| s.version = "0.1.0"\n "sanitized" }))
      end

      context "that uses a conditional" do
        let(:content) do
          "Spec.new { |s| s.version = '0.1.0'\n "\
          "s.post_install_message = \"a\" if true }"
        end
        it "maintains a valid conditional" do
          expect(rewrite).to eq(
            %(Spec.new { |s| s.version = '0.1.0'\n "sanitized" if true })
          )
        end
      end

      context "that uses a heredoc" do
        let(:content) do
          %(Spec.new do |s|
              s.version = "0.1.0"
              s.post_install_message = <<-DESCRIPTION
                My description
              DESCRIPTION
            end)
        end
        it "removes the whole heredoc" do
          expect(rewrite).to eq(
            "Spec.new do |s|\n              s.version = \"0.1.0\""\
            "\n              \"sanitized\"\n            end"
          )
        end
      end
    end

    describe "version assignment" do
      context "with an assignment to a constant" do
        let(:content) { %(Spec.new { |s| s.version = Example::Version }) }
        it { is_expected.to eq(%(Spec.new { |s| s.version = "1.5.0" })) }

        context "that is fully capitalised" do
          let(:content) { %(Spec.new { |s| s.version = Example::VERSION }) }
          it { is_expected.to eq(%(Spec.new { |s| s.version = "1.5.0" })) }
        end

        context "that is dup-ed" do
          let(:content) { %(Spec.new { |s| s.version = Example::VERSION.dup }) }
          it { is_expected.to eq(%(Spec.new { |s| s.version = "1.5.0" })) }
        end

        context "that is tapped" do
          let(:content) do
            %(Spec.new { |s| s.version = Example::VERSION.dup }.tap { |a| "h" })
          end
          it do
            is_expected.to eq(
              %(Spec.new { |s| s.version = "1.5.0" }.tap { |a| "h" })
            )
          end
        end
      end

      context "with an assignment to a variable" do
        let(:content) { "v = 'a'\n\nSpec.new { |s| s.version = v }" }
        it do
          is_expected.to eq(%(v = 'a'\n\nSpec.new { |s| s.version = "1.5.0" }))
        end
      end

      context "with an assignment to an int" do
        let(:content) { "v = 'a'\n\nSpec.new { |s| s.version = 1 }" }
        it do
          is_expected.to eq(%(v = 'a'\n\nSpec.new { |s| s.version = 1 }))
        end
      end

      context "with an assignment to a File.read" do
        let(:content) { "Spec.new { |s| s.version = File.read('something') }" }
        it do
          is_expected.to eq(%(Spec.new { |s| s.version = "1.5.0" }))
        end
      end

      context "with an assignment to a variable" do
        let(:content) { %(Spec.new { |s| s.version = gem_version }) }
        it { is_expected.to eq(%(Spec.new { |s| s.version = "1.5.0" })) }
      end

      context "with an assignment to a string" do
        let(:content) { %(Spec.new { |s| s.version = "1.4.0" }) }
        # Don't actually do the replacement
        it { is_expected.to eq(%(Spec.new { |s| s.version = "1.4.0" })) }
      end

      # rubocop:disable Lint/InterpolationCheck
      context "with an assignment to a string-interpolated constant" do
        let(:content) { 'Spec.new { |s| s.version = "#{Example::Version}" }' }
        it { is_expected.to eq('Spec.new { |s| s.version = "#{"1.5.0"}" }') }
      end
      # rubocop:enable Lint/InterpolationCheck

      context "with a block" do
        let(:content) { fixture("ruby", "gemspecs", "with_nested_block") }
        specify { expect { sanitizer.rewrite(content) }.to_not raise_error }
      end
    end

    describe "files assignment" do
      context "with an assignment to a method call (File.open)" do
        let(:content) { "Spec.new { |s| s.files = File.open('file.txt') }" }
        it { is_expected.to eq("Spec.new { |s| s.files = [] }") }
      end

      context "with an assignment to Dir[..]" do
        let(:content) { fixture("ruby", "gemspecs", "example") }
        it { is_expected.to include("spec.files        = []") }
      end
    end

    describe "require_path assignment" do
      context "with an assignment to Dir[..]" do
        let(:content) { "Spec.new { |s| s.require_paths = Dir['lib'] }" }
        it { is_expected.to eq("Spec.new { |s| s.require_paths = ['lib'] }") }
      end
    end
  end
end
