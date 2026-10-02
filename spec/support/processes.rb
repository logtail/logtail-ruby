require "msgpack"
require "rbconfig"
require "socket"
require "tmpdir"
require "zlib"

# A local stand-in for the Better Stack ingesting host, for tests that run logtail in a separate
# process: it answers every request with 202 and records the message of every line it receives.
class LocalIngestServer
  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @messages = []
    @lock = Mutex.new
    @connections = []
    @thread = Thread.new do
      loop { @connections << Thread.new(@server.accept) { |socket| serve(socket) } }
    end
  end

  # The options for Logtail::LogDevices::HTTP.new that deliver to this server, as Ruby code.
  def device_options
    %(ingesting_host: "127.0.0.1", ingesting_port: #{@server.addr[1]}, ingesting_scheme: "http")
  end

  def messages
    @lock.synchronize { @messages.dup }
  end

  def stop
    @thread.kill.join
    @connections.each { |connection| connection.kill.join }
    @server.close
  end

  private

  def serve(socket)
    while socket.gets
      headers = {}
      while (header = socket.gets) && header != "\r\n"
        name, value = header.split(":", 2)
        headers[name.downcase] = value.strip
      end
      lines = MessagePack.unpack(Zlib::Inflate.inflate(socket.read(headers["content-length"].to_i)))
      @lock.synchronize { @messages.concat(lines.map { |line| line["message"] }) }
      socket.write("HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\n\r\n")
    end
  rescue IOError, SystemCallError
  ensure
    socket.close
  end
end

module ProcessHelpers
  ProcessResult = Struct.new(:stdout, :stderr, :status)

  # Runs the Ruby script in a new process with logtail from lib/ and waits for it to exit, at
  # most `timeout` seconds (generous: TruffleRuby starts slowly on CI).
  def run_ruby(script, timeout: 120)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "script.rb"), script)
      lib = File.expand_path("../../lib", __dir__)
      pid = Process.spawn(RbConfig.ruby, "-I", lib, File.join(dir, "script.rb"),
        out: File.join(dir, "stdout"), err: File.join(dir, "stderr"))
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      status = nil
      until (status = Process.waitpid2(pid, Process::WNOHANG))
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          Process.kill("KILL", pid)
          Process.wait(pid)
          raise "The Ruby process didn't exit within #{timeout} seconds:\n#{File.read(File.join(dir, "stderr"))}"
        end
        sleep 0.05
      end
      ProcessResult.new(File.read(File.join(dir, "stdout")), File.read(File.join(dir, "stderr")), status[1])
    end
  end
end

RSpec.configure do |config|
  config.include ProcessHelpers
end
