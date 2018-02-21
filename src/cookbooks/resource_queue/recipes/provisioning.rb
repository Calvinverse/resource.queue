# frozen_string_literal: true

#
# Cookbook Name:: resource_queue
# Recipe:: provisioning
#
# Copyright 2018, P. van der Velde
#

service 'provision.service' do
  action [:enable]
end

file '/etc/init.d/provision_image.sh' do
  action :create
  content <<~BASH
    #!/bin/bash

    function f_provisionImage {
      # Nuke the mnesia database if it exists so that rabbit starts clean
      # and will try to connect to consul to find the cluster
      if [ -f /srv/rabbitmq/dbase/mnesia ]; then
        rm -rf /srv/rabbitmq/dbase/mnesia
      fi
    }
  BASH
  mode '755'
end
