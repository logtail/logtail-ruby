require "spec_helper"

describe Logtail::Config do
  describe "#debug_logger" do
    # Ruby before 3.0 warns under `ruby -w` when an unset instance variable is read, and the
    # HTTP device reads the debug logger on every connection attempt.
    it "can be read before it is set without an uninitialized instance variable warning" do
      config = described_class.send(:new)
      verbose, $VERBOSE = $VERBOSE, true

      expect { config.debug_logger }.not_to output.to_stderr
    ensure
      $VERBOSE = verbose
    end
  end
end
