# frozen_string_literal: true

require "dependabot/file_updaters/dotnet/nuget"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Dotnet::Nuget do
  it_behaves_like "a dependency file updater"
end
