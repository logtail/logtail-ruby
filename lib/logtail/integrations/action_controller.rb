# frozen_string_literal: true

require 'logtail/integration'
require 'action_controller/log_subscriber'

module Logtail
  module Integrations
    class ActionController < Integration
      class SboLogSubscriber < ::ActionController::LogSubscriber
        def start_processing(event)
          info do
            payload = event.payload
            params = payload[:params].except(*INTERNAL_PARAMS)
            format = extract_format(payload)
            format = format.to_s.upcase if format.is_a?(Symbol)

            Events::ControllerCall.new(
              controller: payload[:controller],
              action: payload[:action],
              format: format,
              params: params
            )
          end
        end

        private

        def extract_format(payload)
          if payload.key?(:format)
            payload[:format] # rails > 4.X
          elsif payload.key?(:formats)
            payload[:formats].first # rails 3.X
          end
        end
      end

      def initialize
        require 'action_controller'
        require 'logtail/integrations/active_support/log_subscriber_interface'
      rescue LoadError => e
        raise RequirementNotMetError.new(e.message)
      end

      def integrate!
        return true if subscriber_interface.subscribed?(SboLogSubscriber)

        subscriber_interface.unsubscribe!(:action_controller, ::ActionController::LogSubscriber)
        SboLogSubscriber.attach_to(:action_controller)
      end

      def subscriber_interface
        Logtail::Integrations::ActiveSupport::LogSubscriberInterface
      end
    end
  end
end
