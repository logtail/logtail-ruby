require "bundler/gem_tasks"
require "logtail"

def puts_with_level(message, level = :info)
  case level
  when :info
    puts("\e[31m#{message}\e[0m")
  when :error
    puts("\e[31m#{message}\e[0m")
  when :success
    puts("\e[32m#{message}\e[0m")
  else
    puts(message)
  end
end

task :test_the_pipes, [:source_token] do |t, args|
  support_email = "hello@betterstack.com"
  # Do not modify below this line. It's important to keep the `Logtail::Logger`
  # because it provides an API for logging structured data and capturing context.
  header = <<~HEREDOC
    ### I want our own pixelart too, but no time for that for now ###
  HEREDOC

  puts header

  current_context = Logtail::CurrentContext.instance.snapshot
  entry = Logtail::LogEntry.new(:info, Time.now, nil, "Testing the pipes (click the inspect icon to view more details)", current_context, nil)
  http_device = Logtail::LogDevices::HTTP.new(args.source_token, flush_continuously: false)
  response = http_device.deliver_one(entry)
  if response.is_a?(Exception)
    message = <<~HEREDOC
        Unable to deliver logs.
        Here's what we received from the Better Stack Telemetry API:
        #{response.inspect}
        If you continue to have trouble please contact support:
        #{support_email}
    HEREDOC
    puts_with_level(message, :error)
  elsif response.is_a?(Net::HTTPResponse)
    if response.code.start_with? '2'
      puts_with_level("Logs successfully sent! View them at https://telemetry.betterstack.com",
        :success)
    else
      message =
        <<~HEREDOC
        Unable to deliver logs.
        We received a #{response.code} response from the Better Stack Telemetry API:
        #{response.body.inspect}
        If you continue to have trouble please contact support:
        #{support_email}
      HEREDOC
      puts_with_level(message, :error)
    end
  end
end

task :console do
  require 'irb'
  require 'irb/completion'
  require 'logtail'
  $VERBOSE = nil

  def reload!
    files = $LOADED_FEATURES.select { |feat| feat =~ /\/logtail\// }
    files.each { |file| load file }
    "reloaded"
  end

  ARGV.clear
  IRB.start
end
