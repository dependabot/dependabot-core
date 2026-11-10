# typed: false
# frozen_string_literal: true

# Sorbet cannot resolve the content fixture defined only in child contexts.

require "spec_helper"
require "dependabot/go_modules/go_work_parser"

RSpec.describe Dependabot::GoModules::GoWorkParser do
  describe ".use_paths" do
    subject(:paths) { described_class.use_paths(content) }

    context "with a multi-line use block containing root and subdirs" do
      let(:content) do
        <<~GOWORK
          go 1.21

          use (
            .
            ./libs
            ./services
          )
        GOWORK
      end

      it { is_expected.to eq([".", "libs", "services"]) }
    end

    context "with a single-line use for root module (use .)" do
      let(:content) { "use ." }

      it { is_expected.to eq(["."]) }
    end

    context "with a single-line use for a subdirectory (use ./sub/dir)" do
      let(:content) { "use ./sub/dir" }

      it { is_expected.to eq(["sub/dir"]) }
    end

    context "with a single-line use directive with a trailing inline comment" do
      let(:content) { "use ./sub/dir // some comment" }

      it { is_expected.to eq(["sub/dir"]) }
    end

    context "with inline comments on use lines" do
      let(:content) do
        <<~GOWORK
          use (
            ./libs // some comment
            ./services
          )
        GOWORK
      end

      it { is_expected.to eq(%w(libs services)) }
    end

    context "with the enable_go_work_version_sync experiment enabled" do
      before { Dependabot::Experiments.register(:enable_go_work_version_sync, true) }

      after { Dependabot::Experiments.reset! }

      context "with a single-line use for a directory without a ./ prefix" do
        let(:content) { "use libs" }

        it { is_expected.to eq(["libs"]) }
      end

      context "with a quoted single-line use directive" do
        let(:content) { %(use "./libs" // some comment) }

        it { is_expected.to eq(["libs"]) }
      end

      context "with mixed spaces and tabs before an escaped quoted path" do
        let(:content) { "use \t \t\"./libs\\u002fapi\"\n" }

        it { is_expected.to eq(["libs/api"]) }
      end

      context "with similarly prefixed non-use directives" do
        let(:content) { "useful ./ignored\nuseful(\nuse./also-ignored\nuse ./libs\n" }

        it { is_expected.to eq(["libs"]) }
      end

      context "with no whitespace before a use block" do
        let(:content) { "use(\n\t./libs\n\t./services\n)\n" }

        it { is_expected.to eq(%w(libs services)) }
      end

      context "with no whitespace before an empty use block" do
        let(:content) { "use() // empty\nuse ./libs\n" }

        it "does not read subsequent directives as block entries" do
          expect(paths).to eq(["libs"])
        end
      end

      context "with long runs of tabs after use" do
        let(:tabs) { "\t\t" * 50_000 }
        let(:content) { "use\t#{tabs}./libs\nuse\t#{tabs}(\n\t./services\n)\n" }

        it "parses single-line and block paths" do
          expect(paths).to eq(%w(libs services))
        end

        context "without a path on the same line" do
          let(:content) { "use\t#{tabs}\nuse ./libs\n" }

          it "does not consume the next directive as a path" do
            expect(paths).to eq(["libs"])
          end
        end
      end

      context "with quoted and unprefixed entries in a use block" do
        let(:content) do
          <<~GOWORK
            use (
              "./libs"
              services // some comment
              "./sdk/go"
            )
          GOWORK
        end

        it { is_expected.to eq(%w(libs services sdk/go)) }
      end

      ["()", "( )", "(\t)"].each do |empty_block|
        context "with an empty #{empty_block} use block" do
          let(:content) { "use #{empty_block} // empty\n\ngo 1.21\nuse ./libs\n" }

          it "does not read subsequent directives as block entries" do
            expect(paths).to eq(["libs"])
          end
        end
      end

      context "with a closing parenthesis in a use block's opening comment" do
        let(:content) { "use ( // not closed by this )\n\t./libs\n)\nuse ./services\n" }

        it { is_expected.to eq(%w(libs services)) }
      end

      %w(./libs/ ./libs/./ .//libs ./libs// ./libs/../libs).each do |path|
        context "with the non-canonical workspace path #{path}" do
          let(:content) { "use \"#{path}\"\nuse (\n\t\"#{path}\"\n)\n" }

          it "returns the canonical member path once" do
            expect(paths).to eq(["libs"])
          end
        end
      end

      context "with multiple spellings of the root module" do
        let(:content) { "use .\nuse ./\nuse \"././\"\nuse \"./libs/..\"\n" }

        it { is_expected.to eq(["."]) }
      end

      context "with absolute and parent-relative paths" do
        let(:content) { "use \"/libs//api/\"\nuse \"../libs/./\"\n" }

        it "preserves their scope for callers to validate" do
          expect(paths).to eq(["/libs/api", "../libs"])
        end
      end

      context "with an empty quoted path" do
        let(:content) { 'use ""' }

        it "does not turn it into the root module" do
          expect(paths).to be_empty
        end
      end

      context "with a null byte in a decoded path" do
        let(:content) { 'use "./libs/\000api"' }

        it "reports an invalid workspace path" do
          expect { paths }.to raise_error(Dependabot::DependencyFileNotParseable, /null byte/)
        end
      end

      {
        "Unicode escapes" => ['"./libs\u002fapi"', "libs/api"],
        "long Unicode escapes" => ['"./libs\U0000002fapi"', "libs/api"],
        "hexadecimal escapes" => ['"./libs\x2fapi"', "libs/api"],
        "octal escapes" => ['"./libs\057api"', "libs/api"],
        "escaped quotes" => ['"./libs/\"api\""', 'libs/"api"'],
        "escaped backslashes" => ['"./libs/\\\\u002fapi"', 'libs/\u002fapi'],
        "control character escapes" => ['"./libs/\a\b\f\n\r\t\v"', "libs/\a\b\f\n\r\t\v"],
        "Unicode code points" => ['"./libs/\u00e9\U0001f600"', "libs/\u00e9\u{1f600}"],
        "UTF-8 byte escapes" => ['"./libs/\xc3\xa9"', "libs/\u00e9"],
        "UTF-8 octal byte escapes" => ['"./libs/\303\251"', "libs/\u00e9"],
        "quoted parentheses and comment markers" => ['"./libs/(api)//v2"', "libs/(api)/v2"]
      }.each do |description, (quoted_path, expected_path)|
        context "with #{description} in a quoted single-line path" do
          let(:content) { "use #{quoted_path} // member\n" }

          it { is_expected.to eq([expected_path]) }
        end

        context "with #{description} in a quoted block path" do
          let(:content) { "use (\n\t#{quoted_path} // member\n)\n" }

          it { is_expected.to eq([expected_path]) }
        end
      end

      context "with equivalent escaped and unescaped paths" do
        let(:content) do
          <<~'GOWORK'
            use (
              ./libs/api
              "./libs\u002fapi"
              "\u002e/libs/api"
            )
          GOWORK
        end

        it { is_expected.to eq(["libs/api"]) }
      end

      [
        '"./libs/\q"',
        '"./libs/\/"',
        '"./libs/\x2"',
        '"./libs/\u002"',
        '"./libs/\U0000002"',
        '"./libs/\400"',
        '"./libs/\uD800"',
        '"./libs/\U00110000"',
        '"./libs/unterminated'
      ].each do |invalid_path|
        context "with an invalid Go string #{invalid_path.inspect}" do
          let(:content) { "use #{invalid_path}\n" }

          it "reports the invalid workspace file" do
            expect { paths }.to raise_error(Dependabot::DependencyFileNotParseable)
          end
        end
      end
    end

    context "with the enable_go_work_version_sync experiment disabled" do
      context "with no whitespace before a use block" do
        let(:content) { "use(\n\t./libs\n)\n" }

        it "preserves legacy parsing" do
          expect(paths).to be_empty
        end
      end

      context "with non-canonical workspace paths" do
        let(:content) { "use ./libs/./\nuse (\n\t\"./services/\"\n)\n" }

        it "does not change legacy path normalization" do
          expect(paths).to eq(['"./services/"', "libs/./"])
        end
      end

      context "with a single-line use for a directory without a ./ prefix" do
        let(:content) { "use libs" }

        it { is_expected.to eq([]) }
      end

      context "with quoted entries" do
        let(:content) do
          <<~GOWORK
            use "./api"
            use (
              "./libs"
            )
          GOWORK
        end

        context "with escaped paths" do
          let(:content) do
            <<~'GOWORK'
              use "./libs\u002fapi"
              use (
                "./libs\u002fapi"
              )
            GOWORK
          end

          it "retains the legacy block entry without decoding it" do
            expect(paths).to eq(['"./libs\u002fapi"'])
          end
        end

        it "keeps the previous behaviour" do
          expect(paths).to eq(['"./libs"'])
        end
      end
    end

    context "with mixed block and single-line use directives" do
      let(:content) do
        <<~GOWORK
          go 1.21
          use (
            ./api
          )
          use ./worker
        GOWORK
      end

      it { is_expected.to eq(%w(api worker)) }
    end

    context "with duplicate paths" do
      let(:content) do
        <<~GOWORK
          use (
            ./api
            ./api
          )
        GOWORK
      end

      it "deduplicates" do
        expect(paths).to eq(%w(api))
      end
    end

    context "with empty content" do
      let(:content) { "" }

      it { is_expected.to eq([]) }
    end

    context "with whitespace-only content" do
      let(:content) { "   \n\n   " }

      it { is_expected.to eq([]) }
    end

    context "with a go.work containing toolchain and godebug directives" do
      let(:content) do
        <<~GOWORK
          go 1.21
          toolchain go1.21.0
          godebug default=go1.21

          use (
            .
            ./cmd
          )
        GOWORK
      end

      it "ignores non-use directives" do
        expect(paths).to eq([".", "cmd"])
      end
    end
  end
end
