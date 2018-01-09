# frozen_string_literal: true

require "dependabot/file_updaters/c_sharp/nuget"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::CSharp::Nuget do
  it_behaves_like "a dependency file updater"
end
