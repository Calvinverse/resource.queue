# frozen_string_literal: true

require 'spec_helper'

describe 'resource_queue::rabbitmq' do
  context 'installs RabbitMQ' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'installs the RabbitMQ service' do
      expect(chef_run).to include_recipe('rabbitmq::default')
      expect(chef_run).to include_recipe('rabbitmq::mgmt_console')
    end

    it 'enable the rabbit-mq service' do
      expect(chef_run).to enable_service('rabbitmq-server')
    end
  end

  context 'configures the firewall for RabbitMQ' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'opens the RabbitMQ HTTP port' do
      expect(chef_run).to create_firewall_rule('rabbitmq-http').with(
        command: :allow,
        dest_port: 15_672,
        direction: :in
      )
    end

    it 'opens the RabbitMQ AMQP port' do
      expect(chef_run).to create_firewall_rule('rabbitmq-amqp').with(
        command: :allow,
        dest_port: 5672,
        direction: :in
      )
    end
  end

  context 'registers the service with consul' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    consul_rabbitmq_config_content = <<~JSON
      {
        "services": [
          {
            "enableTagOverride": false,
            "id": "rabbitmq.amqp",
            "name": "queue",
            "port": 5672,
            "tags": [
              "amqp"
            ]
          },
          {
            "checks": [
              {
                "http": "http://consul:c0nsul@localhost:15672/api/aliveness-test/health",
                "id": "rabbitmq_health",
                "interval": "15s",
                "method": "GET",
                "name": "RabbitMQ health",
                "timeout": "5s"
              }
            ],
            "enableTagOverride": false,
            "id": "rabbitmq.http",
            "name": "queue",
            "port": 15672,
            "tags": [
              "http",
              "management",
              "edgeproxyprefix-/services/queue strip=/services/queue"
            ]
          }
        ]
      }
    JSON
    it 'creates the /etc/consul/conf.d/rabbitmq.json' do
      expect(chef_run).to create_file('/etc/consul/conf.d/rabbitmq.json')
        .with_content(consul_rabbitmq_config_content)
    end
  end
end
