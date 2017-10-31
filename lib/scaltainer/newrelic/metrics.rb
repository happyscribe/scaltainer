module Newrelic
  class Metrics
    def initialize(license_key)
      @headers = {"X-Api-Key" => license_key}
      @base_url = "https://api.newrelic.com/v2"
    end

    # https://docs.newrelic.com/docs/apis/rest-api-v2/application-examples-v2/average-response-time-examples-v2
    def get_avg_response_time(app_id, from, to)
      url = "#{@base_url}/applications/#{app_id}/metrics/data.json"
      conn = Excon.new(url)
      time_range = "from=#{from.iso8601}&to=#{to.iso8601}"

      metric_names = "names[]=HttpDispatcher&values[]=average_call_time&values[]=call_count"
      response = request(conn, metric_names, time_range)
      http_call_count, http_average_call_time = response["call_count"], response["average_call_time"]

      metric_names = "names[]=WebFrontend/QueueTime&values[]=call_count&values[]=average_response_time"
      response = request(conn, metric_names, time_range)
      webfe_call_count, webfe_average_response_time = response["call_count"], response["average_response_time"]

      http_average_call_time + (1.0 * webfe_call_count * webfe_average_response_time / http_call_count)
    end

  private

    def request(conn, metric_names, time_range)
      response = conn.get(headers: @headers, query: "#{metric_names}&#{time_range}&summarize=true")
      body = JSON.parse(response.body)
      body["metric_data"]["metrics"][0]["timeslices"][0]["values"]
    end

  end
end