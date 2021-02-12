require "logtail/util"
require "logtail/event"
module Logtail
  module Events
    # @private
    class TemplateRender < Logtail::Event
      attr_reader :message, :name, :duration_ms

      def initialize(attributes)
        @name = attributes[:name]
        @duration_ms = attributes[:duration_ms]
        @message = attributes[:message]
      end

      def to_hash
        {
          template_rendered: Util::NonNilHashBuilder.build do |h|
            h.add(:name, name)
            h.add(:duration_ms, duration_ms)
          end
        }
      end
    end
  end
end
