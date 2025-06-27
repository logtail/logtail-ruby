# This file showcases usage of logtail on Ruby projects
# For more information visit https://github.com/logtail/logtail-ruby

# SETUP

# Include logtail library
require "logtail"

# Check for program arguments
if ARGV.length != 2
    puts "Program needs source token and ingesting host to run. Run the program as followed\nbundle exec ruby main.rb <source_token> <ingesting_host>"
    exit
end
# Create logger
http_device = Logtail::LogDevices::HTTP.new(ARGV[0], ingesting_host: ARGV[1])
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
logger.fatal("Application crash! Needs to be fixed ASAP!")

puts "All done! You can check your logs now."
