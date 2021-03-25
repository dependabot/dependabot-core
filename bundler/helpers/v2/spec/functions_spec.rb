# frozen_string_literal: true

require "native_spec_helper"

RSpec.describe Functions do
  # Verify v1 method signatures are exist, but raise as NYI
  {
    jfrog_source: %i(dir gemfile_name credentials using_bundler2)
  }.each do |function, kwargs|
    describe "::#{function}" do
      let(:args) do
        kwargs.inject({}) do |args, keyword|
          args.merge({ keyword => anything })
        end
      end

      it "raises a NYI" do
        expect { Functions.send(function, **args) }.to raise_error(Functions::NotImplementedError)
      end
    end
  end
end
