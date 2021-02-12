require "logtail/events/error"

module Logtail
  module Events
    # DEPRECATION: This class is deprecated in favor of using {Logtail:Events:Error}.
    # @private
    class Exception < Error
    end
  end
end