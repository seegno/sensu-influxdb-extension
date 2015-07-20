# Requirements
`influxdb` ruby gem

# Usage
The configuration options are pretty straight forward.

Metrics are inserted into the database with a table per check name. So if you're using the `metrics-memory.rb` plugin, you'd have a series in the defined database called `full_hostname .metric.type` with the following columns:

Ex:
select * from full_hostname.memory.free

The following series would be generated:
```
time	        sequence_number	  value
1437403355000	6523755600001	  4788113408
```

## Extension not a handler
Note that the first push of this was a handler that could be called via `pipe`. This is now an actual extension that's more performant since it's actually in the sensu-server runtime. Additionally it's now using batch submission to InfluxDB by writing all the points for a given series at once.

Just drop the file in `/etc/sensu/extensions` and add it to your `metrics` configuration (`/etc/sensu/conf.d/handlers/metrics.json`:

```json
{
  "checks": {
    "metric_memory": {
      "type": "metric",
      "command": "/opt/sensu/embedded/bin/ruby /etc/sensu/plugins/metrics/metrics-memory.rb",
      "handlers": ["influxdb"],
      "subscribers": ["all"],
      "interval": 60
    }
  }
}

```
In the check config, an optional `influxdb` section can be added, containing a `database` option. If specified, this overrides the default `database` option in the handler config. This allows events to be written to different influxdb databases on a check-by-check basis.

## Example check config (`/etc/sensu/conf.d/check_foo.json`)

```json
{
  "checks": {
    "foo": {
      "command": "check-foo",
      "handlers": ["metrics"],
      "influxdb": {
        "database": "name"
      }
    }
  }
}
```
## Handler config (`/etc/sensu/conf.d/influxdb.json`)

```json
{
  "influxdb": {
    "host": "localhost",
    "port": "8086",
    "user": "stats",
    "password": "stats",
    "database": "stats",
    "ssl_enable": false,
    "strip_metric": "somevalue"
  }
}
```
