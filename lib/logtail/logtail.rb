# Base (must come first, order matters)
require "logtail/version"
require "logtail/config"
require "logtail/util"

# Load frameworks

# Other (sorted alphabetically)
require "logtail/contexts"
require "logtail/current_context"
require "logtail/events"
require "logtail/integration"
require "logtail/log_devices"
require "logtail/log_entry"
require "logtail/logger"
require "logtail/timer"
require "logtail/integrator"
require "logtail/integration"

module Logtail
  # Access the main configuration object. Please see {{Logtail::Config}} for more details.
  def self.config
    Config.instance
  end

  # Starts a timer for timing events. Please see {{Logtail::Logtail.start}} for more details.
  def self.start_timer
    Timer.start
  end

  # Adds context to all logs written within the passed block. Please see
  # {{Logtail::CurrentContext.with}} for a more detailed description with examples.
  def self.with_context(context, &block)
    CurrentContext.with(context, &block)
  end
end
