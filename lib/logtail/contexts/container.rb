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

      class << self
        def container_name=(value)
          @container_name = value
        end

        def container_name
          @container_name
        end

        def container_ipv4=(value)
          @container_ipv4 = value
        end

        def container_ipv4
          @container_ipv4
        end

        def container_id=(value)
          @container_id = value
        end

        def container_id
          @container_id
        end
      end

      attr_reader :pid, :thread_id

      def initialize(attributes)
        @pid = attributes[:pid]
        @thread_id = attributes[:thread_id]
      end

      # Builds a hash representation containing simple objects, suitable for serialization (JSON).
      def to_hash
        @to_hash ||= {
          container: Util::NonNilHashBuilder.build do |h|
            h.add(:name, self.class.container_name)
            h.add(:ipv4, self.class.container_ipv4)
            h.add(:id, self.class.container_id)
            h.add(:pid, pid)
            h.add(:thread_id, thread_id)
          end
        }
      end
    end
  end
end
