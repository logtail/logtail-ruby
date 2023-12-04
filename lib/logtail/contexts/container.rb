require "logtail/context"
require "logtail/util"

module Logtail
  module Contexts
    # The container context tracks AWS ECS Fargate information
    #
    # @note This is tracked automatically in {CurrentContext}. When the current context
    #   is initialized, the container context gets added automatically.
    class Container < Context
      attr_reader :name, :ipv4, :id

      def initialize
        @name = ENV['AWS_CONTAINER_NAME']
        @ipv4 = ENV['AWS_CONTAINER_IPV4']
        @id = ENV['AWS_CONTAINER_ID']
      end

      # Builds a hash representation containing simple objects, suitable for serialization (JSON).
      def to_hash
        @to_hash ||= {
          container: Util::NonNilHashBuilder.build do |h|
            h.add(:name, name)
            h.add(:ipv4, ipv4)
            h.add(:id, id)
          end
        }
      end
    end
  end
end
