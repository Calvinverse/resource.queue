# frozen_string_literal: true

#
# Cookbook Name:: resource_queue
# Recipe:: default
#
# Copyright 2018, P. van der Velde
#

# Always make sure that apt is up to date
apt_update 'update' do
  action :update
end

#
# Include the local recipes
#

include_recipe 'resource_queue::firewall'

include_recipe 'resource_queue::meta'
include_recipe 'resource_queue::provisioning'

include_recipe 'resource_queue::erlang'
include_recipe 'resource_queue::rabbitmq'
