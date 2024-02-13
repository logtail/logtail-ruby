require "logtail/util"
require "logtail/event"

module Logtail
  module Events
    # @private
    class ControllerCall < Logtail::Event
      attr_reader :controller, :action, :params, :params_json, :format

      def initialize(attributes)
        @controller = attributes[:controller]
        @action = attributes[:action]
        @params = attributes[:params]

        if @params
          @params_json = @params.to_json
        end

        @format = attributes[:format]
      end

      def message
        message = "Processing by #{controller}##{action}"
        if !message.nil?
          message << " as #{format}"
        end
        if !params.nil? && params.length > 0
          message << "\n  Parameters: #{params.inspect}"
        end
        message
      end

      def to_hash
        {
          controller_called: Util::NonNilHashBuilder.build do |h|
            h.add(:controller, controller)
            h.add(:action, action)
          end
        }
      end
    end
  end
end
