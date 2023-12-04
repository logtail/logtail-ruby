# frozen_string_literal: true

require 'logtail/rack_logger'
require 'logtail/middleware/http_context'
require 'logtail/middleware/http_events'
require 'logtail/middleware/sbo_user_context'

module Logtail
  # An integration represent an integration for an entire library. For example, `Rack`.
  # While the Logtail `Rack` integration is comprised of multiple middlewares, the
  # `Logtail::Integrations::Rack` module is an entire integration that extends this module.
  module Integration
    # Easily sisable entire library integrations. This is like removing the code from
    # Logtail. It will not touch this library and the library will function as it would
    # without Logtail.
    #
    # @example
    #   Logtail::Integrations::ActiveRecord.enabled = false

    class << self
      def enabled=(value)
        @enabled = value
      end

      # Accessor method for {#enabled=}
      def enabled?
        @enabled != false
      end

      # Silences a library's logs. This ensures that logs are not generated at all
      # from this library.
      #
      # @example
      #   Logtail::Integrations::ActiveRecord.silence = true
      def silence=(value)
        @silence = value
      end

      # Accessor method for {#silence=}
      def silence?
        @silence == true
      end

      # Abstract method that each integration must implement.
      def integrate!
        return false unless enabled?

        Integrations::RackLogger.integrate!
      end

      def middlewares
        @middlewares ||= [
          Integrations::HttpContext,
          Integrations::SboUserContext,
          Integrations::HttpEvents
        ].select(&:enabled?)
      end
    end
  end
end
