module Logtail
  class Config
    # Convenience module for accessing the various `Logtail::Middleware::*` classes
    # through the {Logtail::Config} object.
    # For example:
    #
    #     config = Logtail::Config.instance
    #     config.middlewares.http_context.silence = true
    module Middlewares
      extend self

      def http_context
        Logtail::Middlewares::HttpContext
      end

      def http_events
        Logtail::Middlewares::HttpEvents
      end

      def sbo_user_context
        Logtail::Middlewares::SboUserContext
      end
    end
  end
end
