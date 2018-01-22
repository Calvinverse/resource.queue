# frozen_string_literal: true

#
# Cookbook Name:: resource_queue
# Recipe:: vault
#
# Copyright 2017, P. van der Velde
#

#
# INSTALL RABBITMQ
#

include_recipe 'rabbitmq::default'
include_recipe 'rabbitmq::mgmt_console'

# Make sure the vault service doesn't start automatically. This will be changed
# after we have provisioned the box
service 'rabbitmq' do
  action :enable
end

#
# ALLOW RABBITMQ THROUGH THE FIREWALL
#

rabbitmq_http_port = node['rabbitmq']['http_port']
firewall_rule 'rabbitmq-http' do
  command :allow
  description 'Allow RabbitMQ HTTP traffic'
  dest_port rabbitmq_http_port
  direction :in
end

rabbitmq_amqp_port = node['rabbitmq']['amqp_port']
firewall_rule 'rabbitmq-amqp' do
  command :allow
  description 'Allow RabbitMQ AMQP traffic'
  dest_port rabbitmq_amqp_port
  direction :in
end

#
# CONNECT TO CONSUL
#

rabbitmq_vhost '/consul' do
  action :add
end

rabbitmq_user 'consul' do
  action :add
  password ''
  permissions ''
  vhost ''
end

rabbitmq_proxy_path = node['rabbitmq']['proxy_path']
file '/etc/consul/conf.d/rabbitmq.json' do
  action :create
  content <<~JSON
    {
      "services": [
        {
          "enableTagOverride": false,
          "id": "rabbitmq.amqp",
          "name": "queue",
          "port": #{rabbitmq_amqp_port},
          "tags": [
            "amqp",
          ]
        },
        {
          "checks": [
            {
              "http": "http://localhost:#{rabbitmq_http_port}",
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
          "port": #{rabbitmq_http_port},
          "tags": [
            "http",
            "management",
            "edgeproxyprefix-#{rabbitmq_proxy_path} strip=#{rabbitmq_proxy_path}"
          ]
        }
      ]
    }
  JSON
end
