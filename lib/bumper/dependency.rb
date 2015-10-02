class Dependency
  attr_reader :name, :version

  def initialize(name:, version:)
    @name = name
    @version = version
  end
end
