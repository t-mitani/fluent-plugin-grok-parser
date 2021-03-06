require "helper"
require "tempfile"
require "fluent/plugin/parser_grok"

def str2time(str_time, format = nil)
  if format
    Time.strptime(str_time, format).to_i
  else
    Time.parse(str_time).to_i
  end
end

class GrokParserTest < ::Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  class Timestamp < self
    def test_timestamp_iso8601
      internal_test_grok_pattern("%{TIMESTAMP_ISO8601:time}", "Some stuff at 2014-01-01T00:00:00+0900",
                                 event_time("2014-01-01T00:00:00+0900"), {})
    end

    def test_datestamp_rfc822_with_zone
      internal_test_grok_pattern("%{DATESTAMP_RFC822:time}", "Some stuff at Mon Aug 15 2005 15:52:01 UTC",
                                 event_time("Mon Aug 15 2005 15:52:01 UTC"), {})
    end

    def test_datestamp_rfc822_with_numeric_zone
      internal_test_grok_pattern("%{DATESTAMP_RFC2822:time}", "Some stuff at Mon, 15 Aug 2005 15:52:01 +0000",
                                 event_time("Mon, 15 Aug 2005 15:52:01 +0000"), {})
    end

    def test_syslogtimestamp
      internal_test_grok_pattern("%{SYSLOGTIMESTAMP:time}", "Some stuff at Aug 01 00:00:00",
                                 event_time("Aug 01 00:00:00"), {})
    end
  end

  def test_call_for_grok_pattern_not_found
    assert_raise Fluent::Grok::GrokPatternNotFoundError do
      internal_test_grok_pattern("%{THIS_PATTERN_DOESNT_EXIST}", "Some stuff at somewhere", nil, {})
    end
  end

  def test_call_for_multiple_fields
    internal_test_grok_pattern("%{MAC:mac_address} %{IP:ip_address}", "this.wont.match DEAD.BEEF.1234 127.0.0.1", nil,
                               {"mac_address" => "DEAD.BEEF.1234", "ip_address" => "127.0.0.1"})
  end

  def test_call_for_complex_pattern
    internal_test_grok_pattern("%{COMBINEDAPACHELOG}", '127.0.0.1 192.168.0.1 - [28/Feb/2013:12:00:00 +0900] "GET / HTTP/1.1" 200 777 "-" "Opera/12.0"',
                                str2time("28/Feb/2013:12:00:00 +0900", "%d/%b/%Y:%H:%M:%S %z"),
                                {
                                  "clientip"    => "127.0.0.1",
                                  "ident"       => "192.168.0.1",
                                  "auth"        => "-",
                                  "verb"        => "GET",
                                  "request"     => "/",
                                  "httpversion" => "1.1",
                                  "response"    => "200",
                                  "bytes"       => "777",
                                  "referrer"    => "\"-\"",
                                  "agent"       => "\"Opera/12.0\""
                                },
                                "time_key" => "timestamp",
                                "time_format" => "%d/%b/%Y:%H:%M:%S %z"
                              )
  end

  def test_call_for_custom_pattern
    pattern_file = File.new(File.expand_path("../my_pattern", __FILE__), "w")
    pattern_file.write("MY_AWESOME_PATTERN %{GREEDYDATA:message}\n")
    pattern_file.close
    begin
      internal_test_grok_pattern("%{MY_AWESOME_PATTERN:message}", "this is awesome",
                                 nil, {"message" => "this is awesome"},
                                 "custom_pattern_path" => pattern_file.path
                                )
    ensure
      File.delete(pattern_file.path)
    end
  end

  class OptionalType < self
    def test_simple
      internal_test_grok_pattern("%{INT:user_id:integer} paid %{NUMBER:paid_amount:float}",
                                 "12345 paid 6789.10", nil,
                                 {"user_id" => 12345, "paid_amount" => 6789.1 })
    end

    def test_array
      internal_test_grok_pattern("%{GREEDYDATA:message:array}",
                                 "a,b,c,d", nil,
                                 {"message" => %w(a b c d)})
    end

    def test_array_with_delimiter
      internal_test_grok_pattern("%{GREEDYDATA:message:array:|}",
                                 "a|b|c|d", nil,
                                 {"message" => %w(a b c d)})
    end

    def test_timestamp_iso8601
      internal_test_grok_pattern("%{TIMESTAMP_ISO8601:stamp:time}", "Some stuff at 2014-01-01T00:00:00+0900",
                                 nil, {"stamp" => event_time("2014-01-01T00:00:00+0900")})
    end

    def test_datestamp_rfc822_with_zone
      internal_test_grok_pattern("%{DATESTAMP_RFC822:stamp:time}", "Some stuff at Mon Aug 15 2005 15:52:01 UTC",
                                 nil, {"stamp" => event_time("Mon Aug 15 2005 15:52:01 UTC")})
    end

    def test_datestamp_rfc822_with_numeric_zone
      internal_test_grok_pattern("%{DATESTAMP_RFC2822:stamp:time}", "Some stuff at Mon, 15 Aug 2005 15:52:01 +0000",
                                 nil, {"stamp" => event_time("Mon, 15 Aug 2005 15:52:01 +0000")})
    end

    def test_syslogtimestamp
      internal_test_grok_pattern("%{SYSLOGTIMESTAMP:stamp:time}", "Some stuff at Aug 01 00:00:00",
                                 nil, {"stamp" => event_time("Aug 01 00:00:00")})
    end

    def test_timestamp_with_format
      internal_test_grok_pattern("%{TIMESTAMP_ISO8601:stamp:time:%Y-%m-%d %H%M}", "Some stuff at 2014-01-01 1000",
                                 nil, {"stamp" => event_time("2014-01-01 10:00")})
    end
  end

  class NoGrokPatternMatched < self
    def test_with_grok_failure_key
      config = %[
        grok_failure_key grok_failure
        <grok>
          pattern %{PATH:path}
        </grok>
      ]
      expected = {
        "grok_failure" => "No grok pattern matched",
        "message" => "no such pattern"
      }
      d = create_driver(config)
      d.instance.parse("no such pattern") do |_time, record|
        assert_equal(expected, record)
      end
    end

    def test_without_grok_failure_key
      config = %[
        <grok>
          pattern %{PATH:path}
        </grok>
      ]
      expected = {
        "message" => "no such pattern"
      }
      d = create_driver(config)
      d.instance.parse("no such pattern") do |_time, record|
        assert_equal(expected, record)
      end
    end
  end

  def test_no_grok_patterns
    assert_raise Fluent::ConfigError do
      create_driver('')
    end
  end

  def test_invalid_config_value_type
    assert_raise Fluent::ConfigError do
      create_driver(%[
        <grok>
          pattern %{PATH:path:foo}
        </grok>
      ])
    end
  end

  def test_invalid_config_value_type_and_normal_grok_pattern
    d = create_driver(%[
      <grok>
        pattern %{PATH:path:foo}
      </grok>
      <grok>
        pattern %{IP:ip_address}
      </grok>
    ])
    assert_equal(1, d.instance.instance_variable_get(:@grok).parsers.size)
    logs = $log.instance_variable_get(:@logger).instance_variable_get(:@logdev).logs
    error_logs = logs.grep(/error_class/)
    assert_equal(1, error_logs.size)
    error_message = error_logs.first[/error="(.+)"/, 1]
    assert_equal("unknown value conversion for key:'path', type:'foo'", error_message)
  end

  private

  def create_driver(conf)
    Fluent::Test::Driver::Parser.new(Fluent::Plugin::GrokParser).configure(conf)
  end

  def internal_test_grok_pattern(grok_pattern, text, expected_time, expected_record, options = {})
    d = create_driver({"grok_pattern" => grok_pattern}.merge(options))

    # for the new API
    d.instance.parse(text) {|time, record|
      assert_equal(expected_time, time) if expected_time
      assert_equal(expected_record, record)
    }
  end
end
