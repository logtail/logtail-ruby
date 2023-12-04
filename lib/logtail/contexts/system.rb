require "logtail/context"
require "logtail/util"

module Logtail
  module Contexts
    # The system context tracks OS level process information, such as the process ID.
    class System < Context
      attr_reader :hostname, :pid

      def initialize(attributes)
        @hostname = attributes[:hostname]
        @pid = attributes[:pid]
      end

      # Builds a hash representation containing simple objects, suitable for serialization (JSON).
      def to_hash
        @to_hash ||= {
          system: Util::NonNilHashBuilder.build do |h|
            h.add(:hostname, hostname)
            h.add(:pid, pid)
          end
        }
      end
    end
  end
end
