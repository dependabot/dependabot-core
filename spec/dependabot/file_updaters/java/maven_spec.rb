# frozen_string_literal: true

require "spec_helper"
require "dependabot/file_updaters/java/maven"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Java::Maven do
  it_behaves_like "a dependency file updater"
end
