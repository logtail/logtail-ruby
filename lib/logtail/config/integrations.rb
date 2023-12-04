module Logtail
  class Config
    # Convenience module for accessing the various `Logtail::Integration::*` classes
    # through the {Logtail::Config} object.
    # For example:
    #
    #     config = Logtail::Config.instance
    #     config.integrations.rack_logger.silence = true
    module Integrations
      extend self

      def rack_logger
        Logtail::Integration::RackLogger
      end
    end
  end
end
