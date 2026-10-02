module Logtail
  module LogDevices
    class HTTP
      # Represents an attempt to deliver a request. Requests can be retried, hence
      # why we keep track of the number of attempts.
      class RequestAttempt
        attr_reader :attempts, :request, :line_count

        def initialize(req, line_count = nil)
          @attempts = 0
          @request = req
          @line_count = line_count
        end

        def attempted!
          @attempts += 1
        end
      end
    end
  end
end