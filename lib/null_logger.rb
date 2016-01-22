class NullLogger < Logger
  def add(*_args, &_block)
    nil
  end
end
