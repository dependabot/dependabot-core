class DependencyFile
  attr_accessor :name, :content

  def initialize(name:, content:)
    @name = name
    @content = content
  end
end
