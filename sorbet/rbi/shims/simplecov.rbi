# typed: strict
# frozen_string_literal: true

module SimpleCov
  # Zero-parameter configuration blocks run against the SimpleCov singleton.
  sig do
    params(
      profile: T.nilable(T.any(String, Symbol)),
      _arg1: T.nilable(T.proc.bind(T.class_of(SimpleCov)).void)
    ).void
  end
  def self.start(profile = nil, &_arg1); end
end
