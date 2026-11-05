# This file showcases usage of logtail on Ruby projects
# For more information visit https://github.com/logtail/logtail-ruby

# SETUP

# Include logtail library
require "logtail"

# Read the source token and ingesting host from the environment
source_token = ENV["BETTER_STACK_SOURCE_TOKEN"].to_s
ingesting_host = ENV["BETTER_STACK_INGESTING_HOST"].to_s
if source_token.empty? || ingesting_host.empty?
    puts "Program needs source token and ingesting host to run. Run the program as followed\nBETTER_STACK_SOURCE_TOKEN=<source_token> BETTER_STACK_INGESTING_HOST=<ingesting_host> bundle exec ruby main.rb"
    exit 1
end

# Create logger
http_device = Logtail::LogDevices::HTTP.new(source_token, ingesting_host: ingesting_host)
logger = Logtail::Logger.new(http_device)

# Filter logs that shouldn't be sent to Better Stack, see {Logtail::LogEntry} for available attributes
Logtail.config.filter_sent_to_better_stack { |log_entry| log_entry.message.include?("DO_NOT_SEND") }

# LOGGING

# Send debug logs messages using the debug() method
logger.debug("Better Stack is ready!")

# Send informative messages about interesting events using the info() method
logger.info("I am using Better Stack!")

# Send messages about worrying events using the warn() method
# You can also log additional structured data
logger.warn(
    "log structured data",
    item: {
        url: "https://fictional-store.com/item-123",
        price: 100.00
    }
)

# Some messages can be filtered, see {Logtail::Config#filter_sent_to_better_stack} call above
logger.info("This message will not be sent to Better Stack because it contains 'DO_NOT_SEND'")

# Send error messages using the error() method
logger.error("Oops! An error occurred!")

# Send messages about fatal events that caused the app to crash using the fatal() method
# Log a rescued exception with its class, message and backtrace as structured data
begin
    Integer("one hundred")
rescue ArgumentError => exception
    logger.fatal(
        "Application crash! Needs to be fixed ASAP!",
        error: {
            class: exception.class.name,
            message: exception.message,
            backtrace: exception.backtrace
        }
    )
end

# Close the logger to send the remaining logs to Better Stack before the program ends
logger.close

puts "All done! You can check your logs now."
