require "rubygems" if RUBY_VERSION < '1.9.0'
require "em-http"
require "eventmachine"
require "json"

module Sensu::Extension
  class InfluxDB < Handler
    def name
      definition[:name]
    end

    def definition
      {
        type: "extension",
        name: "influxdb"
      }
    end

    def description
      "Outputs metrics to InfluxDB"
    end

    def post_init()
      # NOTE: Making sure we do not get any data from the Main
    end

    def numeric?(value)
      true if Float(value) rescue false
    end

    def run(event_data)
      data = parse_event(event_data)
      values = Array.new()
      metrics = Array.new()

      values.push((data["timestamp"].to_i) * 1000, data["host"])
      data["output"].split(/\n/).each do |line|
        key, value, time = line.split(/\s+/)

        if @settings["influxdb"]["strip_metric"] == "host"
          key = slice_host(key, data["host"])
        elsif @settings["influxdb"]["strip_metric"]
          key.gsub!(/^.*#{@settings['influxdb']['strip_metric']}\.(.*$)/, '\1')
        end

        metrics.push(key)
       
        # cast to numeric for values that look numeric	
	if numeric?(value)
          value = Float(value)
	end

	values.push(value)
      end

      body = [{
        "name" => data["series"],
        "columns" => ["time", "host"].concat(metrics),
        "points" => [values]
      }]

      settings = parse_settings()

      EventMachine::HttpRequest.new("http://#{ settings["host"] }:#{ settings["port"] }/db/#{ settings["database"] }/series?u=#{ settings["user"] }&p=#{ settings["password"] }").post :head => { "content-type" => "application/x-www-form-urlencoded" }, :body => body.to_json
        
      # You need to yield to the caller. The first argument should be the
      # data you want to yield (in the case of handlers, nothing or an error
      # string, and the return status of the extension.
      yield('', 0)
    end

    private
      def parse_event(event_data)
        begin
          event = JSON.parse(event_data)
          data = {
            "duration" => event["check"]["duration"],
            "host" => event["client"]["name"],
            "output" => event["check"]["output"],
            "series" => event["check"]["name"],
            "timestamp" => event["check"]["issued"]
          }
        rescue => e
          puts "Failed to parse event data"
        end
      end

      def parse_settings()
        begin
          settings = {
            "database" => @settings["influxdb"]["database"],
            "host" => @settings["influxdb"]["host"],
            "password" => @settings["influxdb"]["password"],
            "port" => @settings["influxdb"]["port"],
            "strip_metric" => @settings["influxdb"]["strip_metric"],
            "timeout" => @settings["influxdb"]["timeout"],
            "user" => @settings["influxdb"]["user"]
          }
        rescue => e
          puts "Failed to parse InfluxDB settings"
        end
        return settings
      end

      def slice_host(slice, prefix)
        prefix.chars().zip(slice.chars()).each do | char1, char2 |
          if char1 != char2
            break
          end
          slice.slice!(char1)
        end
        if slice.chars.first == "."
          slice.slice!(".")
        end
        return slice
      end
  end
end
