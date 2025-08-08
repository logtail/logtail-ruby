# This file showcases thread safety testing of logtail on Ruby projects
# For more information visit https://github.com/logtail/logtail-ruby

# SETUP

# Include logtail library
require "logtail"

# Check for program arguments
if ARGV.length != 2
    puts "Program needs source token and ingesting host to run. Run the program as followed\nbundle exec ruby main.rb <source_token> <ingesting_host>"
    exit
end

# Configuration
source_token = ARGV[0]
ingesting_host = ARGV[1]
thread_count = 100
iterations_per_thread = 100

# Thread safety test
puts "Starting thread safety test with #{thread_count} threads..."
puts "Initial thread count: #{Thread.list.size}"

threads = []

thread_count.times do |thread_index|
  threads << Thread.new(thread_index) do |index|
    iterations_per_thread.times do |iteration|
      begin
        # Create a new logger instance for each iteration
        http_device = Logtail::LogDevices::HTTP.new(source_token, ingesting_host: ingesting_host)
        logger = Logtail::Logger.new(http_device)
        
        # Log messages
        logger.info("Log message with structured logging.", {
          thread_count:,
          thread_index:,
          iterations_per_thread:,
          iteration:,
        })
        
        # Close logger to ensure that all logs are sent to Better Stack
        logger.close
        
        puts "Thread #{index}: Completed iteration #{iteration + 1}"
      rescue => e
        puts "Thread #{index}: Error in iteration #{iteration + 1}: #{e.message}"
      end
    end
  end
end

# Monitor thread count while threads are running
monitoring_thread = Thread.new do
  while threads.any?(&:alive?)
    puts "Current thread count: #{Thread.list.size}"
    sleep 0.5
  end
end

# Wait for all threads to complete
threads.each(&:join)
monitoring_thread.join

puts "\nThread safety test completed!"
puts "Final thread count: #{Thread.list.size}"
puts "All done! You can check your logs now."
