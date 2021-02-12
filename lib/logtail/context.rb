module Logtail
  # Base class for all `Logtail::Contexts::*` classes.
  # @private
  class Context
    def to_hash
      raise(NotImplementedError.new)
    end
  end
end
