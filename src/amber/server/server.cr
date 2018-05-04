require "./cluster"
require "./ssl"

module Amber
  class Server
    include Amber::DSL::Server
    alias WebSocketAdapter = WebSockets::Adapters::RedisAdapter.class | WebSockets::Adapters::MemoryAdapter.class
    property pubsub_adapter : WebSocketAdapter = WebSockets::Adapters::MemoryAdapter
    getter handler = Pipe::Pipeline.new
    getter router = Router::Router.new

    def self.instance
      @@instance ||= new
    end

    def self.start
      instance.run
    end

    # Configure should probably be deprecated in favor of settings.
    def self.configure
      with self yield instance.settings
    end

    def self.pubsub_adapter
      instance.pubsub_adapter.instance
    end

    def self.router
      instance.router
    end

    def self.handler
      instance.handler
    end

    def initialize
    end

    def project_name
      @project_name ||= settings.name.gsub(/\W/, "_").downcase
    end

    def run
      thread_count = settings.process_count
      if Cluster.master? && thread_count > 1
        thread_count.times { Cluster.fork }
        sleep
      else
        start
      end
    end

    def start
      time = Time.now
      logger.info "#{version.colorize(:light_cyan)} serving application \"#{settings.name.capitalize}\" at #{host_url.colorize(:light_cyan).mode(:underline)}"
      handler.prepare_pipelines
      server = HTTP::Server.new(settings.host, settings.port, handler)
      server.tls = Amber::SSL.new(settings.ssl_key_file.not_nil!, settings.ssl_cert_file.not_nil!).generate_tls if ssl_enabled?

      Signal::INT.trap do
        Signal::INT.reset
        logger.info "Shutting down Amber"
        server.close
      end

      loop do
        begin
          logger.info "Server started in #{Amber.env.colorize(:yellow)}."
          logger.info "Startup Time #{Time.now - time}".colorize(:white)
          server.listen(settings.port_reuse)
          break
        rescue e : Errno
          if e.errno == Errno::EMFILE
            logger.error e.message
            logger.info "Restarting server..."
            sleep 1
          else
            logger.error e.message
            break
          end
        end
      end
    end

    def version
      "Amber #{Amber::VERSION}"
    end

    def host_url
      "#{scheme}://#{settings.host}:#{settings.port}"
    end

    def ssl_enabled?
      settings.ssl_key_file && settings.ssl_cert_file
    end

    def scheme
      ssl_enabled? ? "https" : "http"
    end

    def logger
      Amber.logger
    end

    def settings
      Amber.settings
    end
  end
end
