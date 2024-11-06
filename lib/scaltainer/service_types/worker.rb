module Scaltainer
  class ServiceTypeWorker < ServiceTypeBase
    def initialize(app_endpoint = nil)
      super
    end

    def get_metrics(services)
      super
      begin
        response = Excon.get(@app_endpoint)
        m = JSON.parse(response.body)
        m.reduce({}){|hash, item| hash.merge!({item["name"] => item["value"]})}
      rescue JSON::ParserError => e
        raise ConfigurationError.new "app_endpoint returned non json response: #{response.body[0..128]}"
      rescue TypeError => e
        raise ConfigurationError.new "app_endpoint returned unexpected json response: #{response.body[0..128]}"
      rescue => e
        raise NetworkError.new "Could not retrieve metrics from application endpoint: #{@app_endpoint}.\n#{e.message}"
      end
    end

    def determine_desired_replicas(metric, service_config, current_replicas, logger)
      super
      raise ConfigurationError.new "Missing ratio in worker resource configuration" unless service_config["ratio"]
      if !metric.is_a?(Integer) || metric < 0
        raise ConfigurationError.new "#{metric} is an invalid metric value, must be a non-negative number" 
      end
      
      target_replicas = (metric * 1.0 / service_config["ratio"]).ceil
      
      # Apply scaling quantities
      upscale_quantity = service_config["upscale_quantity"] || Float::INFINITY
      downscale_quantity = service_config["downscale_quantity"] || Float::INFINITY
      
      desired_replicas = if target_replicas > current_replicas
        [target_replicas, current_replicas + upscale_quantity].min
      else
        [target_replicas, current_replicas - downscale_quantity].max
      end.to_i

      if desired_replicas != target_replicas
        if target_replicas > current_replicas
          logger.info "Desired replicas #{desired_replicas} limited by upscale_quantity #{upscale_quantity} from target #{target_replicas}"
        else
          logger.info "Desired replicas #{desired_replicas} limited by downscale_quantity #{downscale_quantity} from target #{target_replicas}"
        end
      end

      desired_replicas
    end

    def to_s
      "Worker"
    end
  end
end
