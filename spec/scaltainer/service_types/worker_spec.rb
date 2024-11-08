require 'spec_helper'

include Scaltainer

describe ServiceTypeWorker do
  let(:logger) { double(Logger) }
  
  before do
    allow(logger).to receive(:info)  # Allow logger to receive info messages
  end

  describe '#get_metrics' do
    let(:endpoint_host) { 'my-endpoint.com' }
    let(:endpoint) { "http://#{endpoint_host}/" }
    let(:worker_type) { ServiceTypeWorker.new endpoint }
    let(:services) { {w1: {}, w2: {}} }
    let(:response_body) { 'override me in tests below' }

    before {
      Excon.stub({
        method: :get, host: endpoint_host, path: '/'
      }, {
        body: response_body, status: 200
      })
    }

    context 'when endpoint returns valid json' do
      let(:response_body) {
        '[{"name":"worker1","value":10},{"name":"worker2","value":20}]'
      }
      let(:metrics) {
        {"worker1" => 10, "worker2" => 20}
      }

      it 'gets metrics from app endpoint' do
        expect(worker_type.get_metrics(services)).to eq metrics
      end
    end

    context 'when endpoint returns non json response' do
      let(:response_body) {
        'not json'
      }

      it 'raises ConfigurationError' do
        expect{worker_type.get_metrics(services)}.to \
          raise_exception ConfigurationError, /non json response/
      end
    end

    context 'when endpoint returns unexpected json response' do
      let(:response_body) {
        '{"name":"worker1","value":10}'
      }

      it 'raises ConfigurationError' do
        expect{worker_type.get_metrics(services)}.to \
          raise_exception ConfigurationError, /unexpected json response/
      end
    end

    context 'when connection fails' do
      before {
        Excon.stub({
          method: :get, host: endpoint_host, path: '/'
        }, lambda {|request|
          raise SocketError.new "fake socket error"
        })
      }

      it 'raises NetworkError' do
        expect{worker_type.get_metrics(services)}.to raise_exception NetworkError, /fake/
      end
    end
  end # describe #get_metrics

  describe '#determine_desired_replicas' do
    let(:worker_type) { ServiceTypeWorker.new }

    context 'when ratio is missing' do
      let(:config) { {"no_ratio" => nil} }

      it 'raises ConfigurationError' do
        expect{worker_type.determine_desired_replicas(0, config, 0, logger)}.to \
          raise_exception ConfigurationError, /Missing ratio/
      end
    end

    context 'when ratio is specified' do
      let(:config) { {"ratio" => 3} }

      context 'when metric is not a number' do
        it 'raises ConfigurationError' do
          expect{worker_type.determine_desired_replicas('x', config, 0, logger)}.to \
            raise_exception ConfigurationError, /invalid metric/
        end
      end

      context 'when metric is a negative number' do
        it 'raises ConfigurationError' do
          expect{worker_type.determine_desired_replicas(-1, config, 0, logger)}.to \
            raise_exception ConfigurationError, /invalid metric/
        end
      end

      context 'when metric is a floating point number' do
        it 'raises ConfigurationError' do
          expect{worker_type.determine_desired_replicas(1.2, config, 0, logger)}.to \
            raise_exception ConfigurationError, /invalid metric/
        end
      end

      context 'when metric is valid' do
        it 'computes desired replicas correctly' do
          {'0'=>0,'1'=>1,'3'=>1,'4'=>2,'6'=>2,'7'=>3,'10'=>4,'30'=>10}.each {|metric, replicas|
            expect(worker_type.determine_desired_replicas(metric.to_i, config, 0, logger)).to eq replicas
          }
        end
      end
    end

    context "with scaling quantities" do
      it "respects upscale quantity" do
        config = {"ratio" => 10}
        config["upscale_quantity"] = 2
        worker = described_class.new
        
        expect(worker.determine_desired_replicas(50, config, 1, logger)).to eq(3)  # Would be 5, but limited to +2
        expect(worker.determine_desired_replicas(50, config, 3, logger)).to eq(5)  # Next step
      end

      it "respects downscale quantity" do
        config = {"ratio" => 10}
        config["downscale_quantity"] = 2
        worker = described_class.new
        
        expect(worker.determine_desired_replicas(10, config, 5, logger)).to eq(3)  # Would be 1, but limited to -2
        expect(worker.determine_desired_replicas(10, config, 3, logger)).to eq(1)  # Next step
      end

      it "uses infinity as default for both quantities" do
        config = {"ratio" => 10}
        worker = described_class.new
        
        expect(worker.determine_desired_replicas(50, config, 1, logger)).to eq(5)  # No limit on upscaling
        expect(worker.determine_desired_replicas(10, config, 5, logger)).to eq(1)  # No limit on downscaling
      end
    end
  end # describe #determine_desired_replicas

  describe '#to_s' do
    it 'returns a human readable string' do
      expect("#{ServiceTypeWorker.new}").to eq "Worker"
    end
  end # describe #to_s
end # describe ServiceTypeWorker
