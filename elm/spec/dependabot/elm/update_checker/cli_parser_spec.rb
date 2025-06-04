# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/elm/update_checker/cli_parser"

namespace = Dependabot::Elm::UpdateChecker
RSpec.describe namespace::CliParser do
  def elm_version(version_string)
    Dependabot::Elm::Version.new(version_string)
  end
  describe "#decode_install_preview" do
    subject(:decode_install_preview) { described_class.decode_install_preview(output) }

    context "when a first install is needed" do
      let(:output) do
        %(
Some new packages are needed. Here is the upgrade plan.

  Install:
    Skinney/murmur3 2.0.6
    elm-lang/core 5.1.1
    elm-lang/virtual-dom 2.0.4
    rtfeldman/elm-css 13.1.1
    rtfeldman/elm-css-util 1.0.2
    rtfeldman/hex 1.0.0

Do you approve of this plan? [Y/n]
				)
      end

      it do
        expect(decode_install_preview).to include("rtfeldman/elm-css" => elm_version("13.1.1"))
      end
    end

    context "when an upgrade is needed" do
      let(:output) do
        %{
Some new packages are needed. Here is the upgrade plan.

  Install:
    NoRedInk/datetimepicker 3.0.2
    abadi199/dateparser 1.0.4
    elm-lang/html 2.0.0
    elm-lang/svg 2.0.0
    elm-tools/parser 2.0.1
    elm-tools/parser-primitives 1.0.0
    rluiten/elm-date-extra 9.3.1
  Upgrade:
    rtfeldman/elm-css (13.1.1 => 14.0.0)

Do you approve of this plan? [Y/n]
				}
      end

      it do
        expect(decode_install_preview).to include("rtfeldman/elm-css" => elm_version("14.0.0"))
      end
    end
  end
end
