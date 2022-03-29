# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/requirement_parser"

RSpec.describe Dependabot::Python::RequirementParser do
  def parse(line)
    requirement =
      line.chomp.match(described_class::INSTALL_REQ_WITH_REQUIREMENT)
    return if requirement.nil?

    requirements = requirement[:requirements].to_s.
                   to_enum(:scan, described_class::REQUIREMENT).
                   map do
                     {
                       comparison: Regexp.last_match[:comparison],
                       version: Regexp.last_match[:version]
                     }
                   end

    hashes = requirement[:hashes].to_s.
             to_enum(:scan, described_class::HASH).
             map do
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
      let(:line) { "luigi==1!1.1.0"}
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

      context "with a comment" do
        let(:line) { "luigi==0.1.0 # some comment" }
        its([:name]) { is_expected.to eq "luigi" }
        its([:requirements]) do
          is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
        end
      end

      context "with an optional Jinja dependency" do
        let(:line) do
          "{% if cookiecutter.include_package == 'y' %} luigi==0.1.0 "\
          "{% endif %}"
        end

        its([:name]) { is_expected.to eq "luigi" }
        its([:requirements]) do
          is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
        end
      end

      context "with markers" do
        let(:line) do
          'luigi==0.1.0;python_version>="2.7" and '\
          '(sys_platform == "darwin" or sys_platform == "win32") '
        end
        its([:name]) { is_expected.to eq "luigi" }
        its([:requirements]) do
          is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
        end
        its([:markers]) do
          is_expected.to eq 'python_version>="2.7" and '\
            '(sys_platform == "darwin" or sys_platform == "win32")'
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
          is_expected.to match_array(
            [
              { algorithm: "sha256", hash: "2ccb79b01" },
              { algorithm: "sha256", hash: "2ccb79b02" }
            ]
          )
        end

        context "spread over multiple lines" do
          let(:line) do
            "luigi==0.1.0 \\\n"\
            "    --hash=sha256:2ccb79b01 \\\n"\
            "    --hash=sha256:2ccb79b02"
          end

          its([:hashes]) do
            is_expected.to match_array(
              [
                { algorithm: "sha256", hash: "2ccb79b01" },
                { algorithm: "sha256", hash: "2ccb79b02" }
              ]
            )
          end
        end

        context "and with marker" do
          let(:line) do
            "luigi==0.1.0 ; python_version=='2.7' "\
            "--hash=sha256:2ccb79b01 --hash=sha256:2ccb79b02"
          end
          its([:requirements]) do
            is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
          end
          its([:markers]) do
            is_expected.to eq "python_version=='2.7'"
          end
          its([:hashes]) do
            is_expected.to match_array(
              [
                { algorithm: "sha256", hash: "2ccb79b01" },
                { algorithm: "sha256", hash: "2ccb79b02" }
              ]
            )
          end
        end

        context "spread over multiple lines with marker" do
          let(:line) do
            "luigi==0.1.0 ; python_version=='2.7' \\\n"\
            "    --hash=sha256:2ccb79b01 \\\n"\
            "    --hash=sha256:2ccb79b02"
          end
          its([:requirements]) do
            is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
          end
          its([:markers]) do
            is_expected.to eq "python_version=='2.7'"
          end
          its([:hashes]) do
            is_expected.to match_array(
              [
                { algorithm: "sha256", hash: "2ccb79b01" },
                { algorithm: "sha256", hash: "2ccb79b02" }
              ]
            )
          end
        end
      end
    end

    context "with multiple specifications" do
      let(:line) { "luigi == 0.1.0, <= 1" }
      its([:requirements]) do
        is_expected.to eq([
          { comparison: "==", version: "0.1.0" },
          { comparison: "<=", version: "1" }
        ])
      end

      context "with a comment" do
        let(:line) { "luigi == 0.1.0, <= 1 # some comment" }
        its([:requirements]) do
          is_expected.to eq([
            { comparison: "==", version: "0.1.0" },
            { comparison: "<=", version: "1" }
          ])
        end
      end

      context "with brackets" do
        let(:line) { "luigi (>0.1.0,<2)" }
        its([:requirements]) do
          is_expected.to eq([
            { comparison: ">", version: "0.1.0" },
            { comparison: "<", version: "2" }
          ])
        end
      end
    end
  end
end
