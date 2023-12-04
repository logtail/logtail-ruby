# frozen_string_literal: true

require "logtail/config"
require "logtail/middleware"

module Logtail
  module Integrations
    class SboUserContext < Middleware
      class << self
        # @example Setting your own custom user context
        #   Logtail::Integrations::SboContext.sbo_hash = lambda do |env|
        #     { request_id: env['warden'].request.request_id }
        #   end
        def sbo_hash=(proc)
          if proc && !proc.is_a?(Proc)
            raise ArgumentError.new("The value passed to #sbo_hash must be a Proc")
          end

          @sbo_hash = proc
        end

        attr_reader :sbo_hash
      end

      def call(env)
        computed_hash = get_sbo_hash(env)
        if computed_hash
          CurrentContext.with(
            { 'sbo_usr' => computed_hash }
          ) do
            @app.call(env)
          end
        else
          @app.call(env)
        end
      end

      private

      def get_sbo_hash(env)
        if self.class.sbo_hash.is_a?(Proc)
          Config.instance.debug { "Obtaining user context from the custom user hash" }
          self.class.sbo_hash.call(env)
        else
          Config.instance.debug { "Could not locate any user data" }
        end
      end
    end
  end
end
