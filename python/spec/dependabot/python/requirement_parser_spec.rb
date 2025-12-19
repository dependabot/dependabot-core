# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/requirement_parser"

RSpec.describe Dependabot::Python::RequirementParser do
  def parse(line)
    requirement =
      line.chomp.match(described_class::INSTALL_REQ_WITH_REQUIREMENT)
    return if requirement.nil?

    requirements = requirement[:requirements].to_s
                                             .to_enum(:scan, described_class::REQUIREMENT)
                                             .map do
      {
        comparison: Regexp.last_match[:comparison],
        version: Regexp.last_match[:version]
      }
    end

    hashes = requirement[:hashes].to_s
                                 .to_enum(:scan, described_class::HASH)
                                 .map do
      {
        algorithm: Regexp.last_match[:algorithm],
        hash: Regexp.last_match[:hash]
      }
    end

    {
      name: requirement[:name],
      requirements: requirements,
      hashes: hashes,
      markers: requirement[:markers]
    }
  end

  describe ".parse" do
    subject { parse(line) }

    context "with a blank line" do
      let(:line) { "" }

      it { is_expected.to be_nil }
    end

    context "with just a line break" do
      let(:line) { "\n" }

      it { is_expected.to be_nil }
    end

    context "with a non-requirement line" do
      let(:line) { "# This is just a comment" }

      it { is_expected.to be_nil }
    end

    context "with a Jinja template" do
      let(:line) { "{{ cookiecutter.package_name }}" }

      it { is_expected.to be_nil }
    end

    context "with no specification" do
      let(:line) { "luigi" }

      it { is_expected.to be_nil }
    end

    context "with an epoch specification" do
      let(:line) { "luigi==1!1.1.0" }

      its([:requirements]) do
        is_expected.to eq [{ comparison: "==", version: "1!1.1.0" }]
      end
    end

    context "with a simple specification" do
      let(:line) { "luigi == 0.1.0" }

      its([:requirements]) do
        is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
      end

      context "without spaces" do
        let(:line) { "luigi==0.1.0" }

        its([:name]) { is_expected.to eq "luigi" }

        its([:requirements]) do
          is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
        end
      end

      context "with preceding v" do
        let(:line) { "luigi==v0.1.0" }

        its([:name]) { is_expected.to eq "luigi" }

        its([:requirements]) do
          is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
        end
      end

      context "with a comment" do
        let(:line) { "luigi==0.1.0 # some comment" }

        its([:name]) { is_expected.to eq "luigi" }

        its([:requirements]) do
          is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
        end
      end

      context "with an optional Jinja dependency" do
        let(:line) do
          "{% if cookiecutter.include_package == 'y' %} luigi==0.1.0 " \
            "{% endif %}"
        end

        its([:name]) { is_expected.to eq "luigi" }

        its([:requirements]) do
          is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
        end
      end

      context "with markers" do
        let(:line) do
          'luigi==0.1.0;python_version>="2.7" and ' \
            '(sys_platform == "darwin" or sys_platform == "win32") '
        end

        its([:name]) { is_expected.to eq "luigi" }

        its([:requirements]) do
          is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
        end

        its([:markers]) do
          is_expected.to eq 'python_version>="2.7" and ' \
                            '(sys_platform == "darwin" or sys_platform == "win32")'
        end

        context "with python_version marker" do
          let(:line) { 'luigi==0.1.0;python_version>="3.8"' }

          its([:markers]) { is_expected.to eq 'python_version>="3.8"' }
        end

        context "with python_full_version marker" do
          let(:line) { 'luigi==0.1.0;python_full_version>="3.8.0"' }

          its([:markers]) { is_expected.to eq 'python_full_version>="3.8.0"' }
        end

        context "with os_name marker" do
          let(:line) { 'luigi==0.1.0;os_name=="posix"' }

          its([:markers]) { is_expected.to eq 'os_name=="posix"' }
        end

        context "with sys_platform marker" do
          let(:line) { 'luigi==0.1.0;sys_platform=="linux"' }

          its([:markers]) { is_expected.to eq 'sys_platform=="linux"' }
        end

        context "with platform_release marker" do
          let(:line) { 'luigi==0.1.0;platform_release=="5.10.0"' }

          its([:markers]) { is_expected.to eq 'platform_release=="5.10.0"' }
        end

        context "with platform_system marker" do
          let(:line) { 'luigi==0.1.0;platform_system=="Linux"' }

          its([:markers]) { is_expected.to eq 'platform_system=="Linux"' }
        end

        context "with platform_version marker" do
          let(:line) { 'luigi==0.1.0;platform_version=="#1"' }

          its([:markers]) { is_expected.to eq 'platform_version=="#1"' }
        end

        context "with platform_machine marker" do
          let(:line) { 'luigi==0.1.0;platform_machine=="x86_64"' }

          its([:markers]) { is_expected.to eq 'platform_machine=="x86_64"' }
        end

        context "with platform_python_implementation marker" do
          let(:line) { 'luigi==0.1.0;platform_python_implementation=="CPython"' }

          its([:markers]) { is_expected.to eq 'platform_python_implementation=="CPython"' }
        end

        context "with implementation_name marker" do
          let(:line) { 'luigi==0.1.0;implementation_name=="cpython"' }

          its([:markers]) { is_expected.to eq 'implementation_name=="cpython"' }
        end

        context "with implementation_version marker" do
          let(:line) { 'luigi==0.1.0;implementation_version>="3.8"' }

          its([:markers]) { is_expected.to eq 'implementation_version>="3.8"' }
        end

        context "with whitespace in marker expression" do
          let(:line) { 'luigi==0.1.0;implementation_version  >=  "3.8" and python_version >= "3.8"' }

          its([:markers]) { is_expected.to eq 'implementation_version  >=  "3.8" and python_version >= "3.8"' }
        end
      end

      context "with a local version" do
        let(:line) { "luigi==0.1.0+gc.1" }

        its([:name]) { is_expected.to eq "luigi" }

        its([:requirements]) do
          is_expected.to eq [{ comparison: "==", version: "0.1.0+gc.1" }]
        end
      end

      context "with a hash" do
        let(:line) { "luigi==0.1.0 --hash=sha256:2ccb79b01769d9911" }

        its([:name]) { is_expected.to eq "luigi" }

        its([:requirements]) do
          is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
        end

        its([:hashes]) do
          is_expected.to eq [{ algorithm: "sha256", hash: "2ccb79b01769d9911" }]
        end
      end

      context "with multiple hashes" do
        let(:line) do
          "luigi==0.1.0 --hash=sha256:2ccb79b01 --hash=sha256:2ccb79b02"
        end

        its([:hashes]) do
          is_expected.to contain_exactly(
            { algorithm: "sha256", hash: "2ccb79b01" },
            { algorithm: "sha256", hash: "2ccb79b02" }
          )
        end

        context "when spread over multiple lines" do
          let(:line) do
            "luigi==0.1.0 \\\n" \
              "    --hash=sha256:2ccb79b01 \\\n" \
              "    --hash=sha256:2ccb79b02"
          end

          its([:hashes]) do
            is_expected.to contain_exactly(
              { algorithm: "sha256", hash: "2ccb79b01" },
              { algorithm: "sha256", hash: "2ccb79b02" }
            )
          end
        end

        context "with marker" do
          let(:line) do
            "luigi==0.1.0 ; python_version=='2.7' " \
              "--hash=sha256:2ccb79b01 --hash=sha256:2ccb79b02"
          end

          its([:requirements]) do
            is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
          end

          its([:markers]) do
            is_expected.to eq "python_version=='2.7'"
          end

          its([:hashes]) do
            is_expected.to contain_exactly(
              { algorithm: "sha256", hash: "2ccb79b01" },
              { algorithm: "sha256", hash: "2ccb79b02" }
            )
          end
        end

        context "when spread over multiple lines with marker" do
          let(:line) do
            "luigi==0.1.0 ; python_version=='2.7' \\\n" \
              "    --hash=sha256:2ccb79b01 \\\n" \
              "    --hash=sha256:2ccb79b02"
          end

          its([:requirements]) do
            is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
          end

          its([:markers]) do
            is_expected.to eq "python_version=='2.7'"
          end

          its([:hashes]) do
            is_expected.to contain_exactly(
              { algorithm: "sha256", hash: "2ccb79b01" },
              { algorithm: "sha256", hash: "2ccb79b02" }
            )
          end
        end
      end
    end

    context "with multiple specifications" do
      let(:line) { "luigi == 0.1.0, <= 1" }

      its([:requirements]) do
        is_expected.to eq(
          [
            { comparison: "==", version: "0.1.0" },
            { comparison: "<=", version: "1" }
          ]
        )
      end

      context "with a comment" do
        let(:line) { "luigi == 0.1.0, <= 1 # some comment" }

        its([:requirements]) do
          is_expected.to eq(
            [
              { comparison: "==", version: "0.1.0" },
              { comparison: "<=", version: "1" }
            ]
          )
        end
      end

      context "with brackets" do
        let(:line) { "luigi (>0.1.0,<2)" }

        its([:requirements]) do
          is_expected.to eq(
            [
              { comparison: ">", version: "0.1.0" },
              { comparison: "<", version: "2" }
            ]
          )
        end
      end
    end
  end
end
