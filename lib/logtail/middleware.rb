# frozen_string_literal: true

module Logtail
  class Middleware
    class << self
      def enabled=(value)
        @enabled = value
      end

      def enabled?
        @enabled != false
      end

      def silence=(value)
        @silence = value
      end

      def silence?
        @silence == true
      end

      def middlewares
        @middlewares ||= [
          Middlewares::HttpContext,
          Middlewares::SboUserContext,
          Middlewares::HttpEvents
        ].select(&:enabled?)
      end
    end

    def initialize(app)
      @app = app
    end
  end
end
