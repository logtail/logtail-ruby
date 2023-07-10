# This file showcases usage of logtail on Ruby projects
# For more information visit https://github.com/logtail/logtail-ruby

# SETUP

# Include logtail library
require "logtail"

# Check for program arguments
if ARGV.length != 1
    puts "Program needs source token to run. Run the program as followed\nruby main.rb <source-token>"
    exit
end
# Create logger
http_device = Logtail::LogDevices::HTTP.new(ARGV[0])
logger = Logtail::Logger.new(http_device)

# LOGGING

# Send debug logs messages using the debug() method
logger.debug("Logtail is ready!")

# Send informative messages about interesting events using the info() method
logger.info("I am using Logtail!")

# Send messages about worrying events using the warn() method
# You can also log additional structured data
logger.warn(
    "log structured data",
    item: {
        url: "https://fictional-store.com/item-123",
        price: 100.00
    }
)

# Send error messages using the error() method
logger.error("Oops! An error occurred!")

# Send messages about fatal events that caused the app to crash using the fatal() method
logger.fatal("Application crash! Needs to be fixed ASAP!")

puts "All done! You can check your logs now."
