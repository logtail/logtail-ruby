require "rack"

module Logtail
  class Config
    # Convenience module for accessing the various `Logtail::Integrations::*` classes
    # through the {Logtail::Config} object. Logtail couples configuration with the class
    # responsible for implementing it. This provides for a tighter design, but also
    # requires the user to understand and access the various classes. This module aims
    # to provide a simple ruby-like configuration interface for internal Logtail classes.
    #
    # For example:
    #
    #     config = Logtail::Config.instance
    #     config.integrations.active_record.silence = true
    module Integrations
      extend self

      def http_context
        Logtail::Integrations::Rack::HttpContext
      end

      def http_events
        Logtail::Integrations::HttpEvents
      end

      def sbo_context
        Logtail::Integrations::SboContext
      end
    end
  end
end
