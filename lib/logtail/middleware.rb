# frozen_string_literal: true

module Logtail
  module Integrations
    class Middleware
      class << self
        # @example
        #   Logtail::Integrations::SboContext.enabled = false
        def enabled=(value)
          @enabled = value
        end

        def enabled?
          @enabled != false
        end
      end

      def initialize(app)
        @app = app
      end
    end
  end
end
