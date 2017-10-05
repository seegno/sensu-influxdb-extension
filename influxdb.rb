require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'em-http-request'
require 'eventmachine'
require 'multi_json'

module Sensu::Extension
  class InfluxDB < Handler
    def name
      definition[:name]
    end

    def definition
      {
        type: 'extension',
        name: 'influxdb'
      }
    end

    def description
      'Outputs metrics to InfluxDB'
    end

    def post_init()
      @influx_conf = parse_settings
      logger.info("InfluxDB extension initialiazed using #{@influx_conf['protocol'] }://#{ @influx_conf['host'] }:#{ @influx_conf['port'] } - Defaults : db=#{@influx_conf['database']} precision=#{@influx_conf['time_precision']}")

      @buffer = {}
      @flush_timer = EventMachine::PeriodicTimer.new(@influx_conf['buffer_max_age'].to_i) do
        unless buffer_size == 0
          logger.debug("InfluxDB cache age > #{@influx_conf['buffer_max_age']} : forcing flush")
          flush_buffer
        end
      end
      logger.info("InfluxDB write buffer initiliazed : buffer flushed every #{@influx_conf['buffer_max_size']} points OR every #{@influx_conf['buffer_max_age']} seconds) ")
    end

    def run(event_data)
      event = parse_event(event_data)

      # init event and check data
      body = []
      client = event[:client][:name]
      event[:check][:influxdb][:database] ||= @influx_conf['database']
      event[:check][:time_precision] ||= @influx_conf['time_precision']

      event[:check][:output].split(/\n/).each do |line|
        key, value, time = line.split(/\s+/)
        values = "value=#{value.to_f}"

        if event[:check][:duration]
          values += ",duration=#{event[:check][:duration].to_f}"
        end

        if @influx_conf['strip_metric'] == 'host'
          key = slice_host(key, client)
        elsif @influx_conf['strip_metric']
          key.gsub!(/^.*#{@influx_conf['strip_metric']}\.(.*$)/, '\1')
        end

        # Avoid things break down due to comma in key name
        key.gsub!(',', '\,')
        key.gsub!(/\s/, '\ ')
        key.gsub!('"', '\"')
        key.gsub!("\\"){ "\\\\" }

        # This will merge : default conf tags < check embedded tags < sensu client/host tag
        tags = @influx_conf['tags'].merge(event[:check][:influxdb][:tags]).merge(event[:client][:tags]).merge({'host' => client})
        tags.each do |tag, val|
          key += ",#{tag}=#{val}"
        end

        @buffer[event[:check][:influxdb][:database]] ||= {}
        @buffer[event[:check][:influxdb][:database]][event[:check][:time_precision]] ||= []

        @buffer[event[:check][:influxdb][:database]][event[:check][:time_precision]].push([key, values, time.to_i].join(' '))
        flush_buffer if buffer_size >= @influx_conf['buffer_max_size']
      end

      yield('', 0)
    end

    def stop
      logger.info('Flushing InfluxDB buffer before exiting')
      flush_buffer
      true
    end

    private

    def flush_buffer
      @flush_timer.cancel
      logger.debug('Flushing InfluxDB buffer')
      @buffer.each do |db, tp|
        tp.each do |p, points|
          logger.debug("Sending #{ points.length } points to #{ db } InfluxDB database with precision=#{ p }")

          EventMachine::HttpRequest.new("#{ @influx_conf['protocol'] }://#{ @influx_conf['host'] }:#{ @influx_conf['port'] }/write?db=#{ db }&precision=#{ p }&u=#{ @influx_conf['username'] }&p=#{ @influx_conf['password'] }").post :body => points.join("\n")

        end
        logger.debug("Cleaning buffer for db #{ db }")
        @buffer[db] = {}
      end
    end

    def buffer_size
      sum = @buffer.map { |_db, tp| tp.map { |_p, points| points.length}.inject(:+) }.inject(:+)
      return sum || 0
    end

    def parse_event(event_data)
      begin
        event = MultiJson.load(event_data)

        # default values
        # n, u, ms, s, m, and h (default community plugins use standard epoch date)
        event[:check][:time_precision] ||= nil
        event[:check][:influxdb] ||= {}
        event[:check][:influxdb][:tags] ||= {}
        event[:check][:influxdb][:database] ||= nil

      rescue => e
        logger.error("Failed to parse event data: #{e}")
      end
      return event
    end

    def parse_settings()
      begin
        settings = @settings['influxdb']

        # default values
        settings['tags'] ||= {}
        settings['use_ssl'] ||= false
        settings['time_precision'] ||= 's'
        settings['protocol'] = settings['use_ssl'] ? 'https' : 'http'
        settings['buffer_max_size'] ||= 500
        settings['buffer_max_age'] ||= 6 # seconds
        settings['port'] ||= 8086

      rescue => e
        logger.error("Failed to parse InfluxDB settings #{e}")
      end
      return settings
    end

    def slice_host(slice, prefix)
      prefix.chars.zip(slice.chars).each do |char1, char2|
        break if char1 != char2
        slice.slice!(char1)
      end
      slice.slice!('.') if slice.chars.first == '.'
      return slice
    end

    def logger
      Sensu::Logger.get
    end
  end
end
