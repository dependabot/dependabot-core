# typed: false
# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength

require "spec_helper"
require "dependabot/gradle/update_checker"
require "dependabot/gradle/update_checker/distributions_finder"

RSpec.describe Dependabot::Gradle::UpdateChecker::DistributionsFinder do
  before do
    stub_request(:get, "https://services.gradle.org/versions/all")
      .to_return(
        status: 200,
        body: fixture("gradle_distributions_metadata", "versions_all.json")
      )
  end

  describe "#available_versions" do
    it {
      expect(described_class.available_versions).to eq(%w(
        0.7
        0.8
        0.9
        0.9.1
        0.9.2
        1.0
        1.1
        1.2
        1.3
        1.4
        1.5
        1.6
        1.7
        1.8
        1.9
        1.10
        1.11
        1.12
        2.0
        2.1
        2.2
        2.2.1
        2.3
        2.4
        2.5
        2.6
        2.7
        2.8
        2.9
        2.10
        2.11
        2.12
        2.13
        2.14
        2.14.1
        3.0
        3.1
        3.2
        3.2.1
        3.3
        3.4
        3.4.1
        3.5
        3.5.1
        4.0
        4.0.1
        4.0.2
        4.1
        4.2
        4.2.1
        4.3
        4.3.1
        4.4
        4.4.1
        4.5
        4.5.1
        4.6
        4.7
        4.8
        4.8.1
        4.9
        4.10
        4.10.1
        4.10.2
        4.10.3
        5.0
        5.1
        5.1.1
        5.2
        5.2.1
        5.3
        5.3.1
        5.4
        5.4.1
        5.5
        5.5.1
        5.6
        5.6.1
        5.6.2
        5.6.3
        5.6.4
        6.0
        6.0.1
        6.1
        6.1.1
        6.2
        6.2.1
        6.2.2
        6.3
        6.4
        6.4.1
        6.5
        6.5.1
        6.6
        6.6.1
        6.7
        6.7.1
        6.8
        6.8.1
        6.8.2
        6.8.3
        6.9
        6.9.1
        6.9.2
        6.9.3
        6.9.4
        7.0
        7.0.1
        7.0.2
        7.1
        7.1.1
        7.2
        7.3
        7.3.1
        7.3.2
        7.3.3
        7.4
        7.4.1
        7.4.2
        7.5
        7.5.1
        7.6
        7.6.1
        7.6.2
        7.6.3
        7.6.4
        7.6.5
        7.6.6
        8.0
        8.0.1
        8.0.2
        8.1
        8.1.1
        8.2
        8.2.1
        8.3
        8.4
        8.5
        8.6
        8.7
        8.8
        8.9
        8.10
        8.10.1
        8.10.2
        8.11
        8.11.1
        8.12
        8.12.1
        8.13
        8.14
        8.14.1
        8.14.2
        8.14.3
        9.0.0
      ).map do |version|
        {
          version: Dependabot::Gradle::Version.new(version),
          source_url: "https://services.gradle.org"
        }
      end)
    }
  end
end

# rubocop:enable RSpec/ExampleLength
