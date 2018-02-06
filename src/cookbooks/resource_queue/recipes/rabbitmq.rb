# frozen_string_literal: true

#
# Cookbook Name:: resource_queue
# Recipe:: rabbitmq
#
# Copyright 2017, P. van der Velde
#

#
# INSTALL RABBITMQ
#

# Don't include the managment console until they remove the visualiser
include_recipe 'rabbitmq::default'
include_recipe 'rabbitmq::plugin_management'
include_recipe 'rabbitmq::user_management'
include_recipe 'rabbitmq::virtualhost_management'

#
# SET PERMISSIONS ON DATA PATH
#

rabbitmq_service_path = node['rabbitmq']['service_data_path']
directory rabbitmq_service_path do
  action :create
  group node['rabbitmq']['service_group']
  mode '775'
  owner node['rabbitmq']['service_user']
  recursive true
end

rabbitmq_mnesia_path = node['rabbitmq']['mnesiadir']
directory rabbitmq_mnesia_path do
  action :create
  group node['rabbitmq']['service_group']
  mode '775'
  owner node['rabbitmq']['service_user']
  notifies :restart, "service[#{node['rabbitmq']['service_name']}]"
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
# CONSUL-TEMPLATE FILES
#

consul_template_config_path = node['consul_template']['config_path']
consul_template_template_path = node['consul_template']['template_path']

# cluster name
rabbitmq_cluster_template_file = node['rabbitmq']['consul_template_cluster_file']
file "#{consul_template_template_path}/#{rabbitmq_cluster_template_file}" do
  action :create
  content <<~CONF
    #!/bin/sh

    rabbitmqctl set_cluster_name queue@{{ keyOrDefault "config/services/consul/datacenter" "consul" }}
  CONF
  mode '755'
end

rabbitmq_cluster_script_file = node['rabbitmq']['script_cluster_file']
file "#{consul_template_config_path}/rabbitmq_cluster.hcl" do
  action :create
  content <<~HCL
    # This block defines the configuration for a template. Unlike other blocks,
    # this block may be specified multiple times to configure multiple templates.
    # It is also possible to configure templates via the CLI directly.
    template {
      # This is the source file on disk to use as the input template. This is often
      # called the "Consul Template template". This option is required if not using
      # the `contents` option.
      source = "#{consul_template_template_path}/#{rabbitmq_cluster_template_file}"

      # This is the destination path on disk where the source template will render.
      # If the parent directories do not exist, Consul Template will attempt to
      # create them, unless create_dest_dirs is false.
      destination = "#{rabbitmq_cluster_script_file}"

      # This options tells Consul Template to create the parent directories of the
      # destination path if they do not exist. The default value is true.
      create_dest_dirs = false

      # This is the optional command to run when the template is rendered. The
      # command will only run if the resulting template changes. The command must
      # return within 30s (configurable), and it must have a successful exit code.
      # Consul Template is not a replacement for a process monitor or init system.
      command = "sh #{rabbitmq_cluster_script_file}"

      # This is the maximum amount of time to wait for the optional command to
      # return. Default is 30s.
      command_timeout = "15s"

      # Exit with an error when accessing a struct or map field/key that does not
      # exist. The default behavior will print "<no value>" when accessing a field
      # that does not exist. It is highly recommended you set this to "true" when
      # retrieving secrets from Vault.
      error_on_missing_key = false

      # This is the permission to render the file. If this option is left
      # unspecified, Consul Template will attempt to match the permissions of the
      # file that already exists at the destination path. If no file exists at that
      # path, the permissions are 0644.
      perms = 0755

      # This option backs up the previously rendered template at the destination
      # path before writing a new one. It keeps exactly one backup. This option is
      # useful for preventing accidental changes to the data without having a
      # rollback strategy.
      backup = true

      # These are the delimiters to use in the template. The default is "{{" and
      # "}}", but for some templates, it may be easier to use a different delimiter
      # that does not conflict with the output file itself.
      left_delimiter  = "{{"
      right_delimiter = "}}"

      # This is the `minimum(:maximum)` to wait before rendering a new template to
      # disk and triggering a command, separated by a colon (`:`). If the optional
      # maximum value is omitted, it is assumed to be 4x the required minimum value.
      # This is a numeric time with a unit suffix ("5s"). There is no default value.
      # The wait value for a template takes precedence over any globally-configured
      # wait.
      wait {
        min = "2s"
        max = "10s"
      }
    }
  HCL
  mode '755'
end

# configuration file
rabbitmq_config_template_file = node['rabbitmq']['consul_template_config_file']
file "#{consul_template_template_path}/#{rabbitmq_config_template_file}" do
  action :create
  content <<~CONF
    %%%
    %% Generated by Consul-Template
    %%%

    [
      {
        kernel, []
      },
      {
        rabbitmq_management, [
          {
            listener, [
              {
                port, #{rabbitmq_http_port}
              }
            ]
          }
        ]
      },
      {
        rabbit, [
          {
            auth_backends, [
              rabbit_auth_backend_ldap,
              rabbit_auth_backend_internal
            ]
          },
          {
            default_pass, <<"guest">>
          },
          {
            default_user, <<"guest">>
          },
          {
            heartbeat, 60
          },
          {
            log_levels, [{ connection, info }]
          },
          {
            loopback_users, [
              <<"guest">>,
              <<"consul">>
            ]
          },
          {
            reverse_dns_lookups, true
          },
          {
            tcp_listen_options, [
              binary,
              {packet,raw},
              {reuseaddr,true},
              {backlog,128},
              {nodelay,true},
              {exit_on_close,false},
              {keepalive,false},
              {linger, {true,0}}
            ]
          }
        ]
    {{ if keyExists "config/environment/directory/initialized" }}
      },
      {
        rabbitmq_auth_backend_ldap, [
          {
            servers, [
      {{ range ls "config/environment/directory/endpoints" }}
              "{{ .Value }}"
      {{ end }}
            ]
          },
          {
            dn_lookup_attribute, "userPrincipalName"
          },
          {
            dn_lookup_base, "{{ keyOrDefault "/config/environment/directory/query/users/lookupbase" "DC=example,DC=com" }}"
          },
          {
            group_lookup_base, "{{ keyOrDefault "/config/environment/directory/query/groups/lookupbase" "DC=example,DC=com" }}"
          },
          {
            other_bind, as_user
          },
          {
            vhost_access_query, { in_group, "{{ keyOrDefault "/config/environment/directory/query/groups/queue/administrators" "" }}" }
          },
          {
            tag_queries, [
              {
                administrator, { in_group, "{{ keyOrDefault "/config/environment/directory/query/groups/queue/administrators" "" }}" }
              },
              {
                management, { constant, false }
              }
            ]
          }
        ]
      }
    {{ else }}
      }
    {{ end }}
    ].
  CONF
  mode '755'
end

rabbitmq_config_file = node['rabbitmq']['config_file']
file "#{consul_template_config_path}/rabbitmq_config.hcl" do
  action :create
  content <<~HCL
    # This block defines the configuration for a template. Unlike other blocks,
    # this block may be specified multiple times to configure multiple templates.
    # It is also possible to configure templates via the CLI directly.
    template {
      # This is the source file on disk to use as the input template. This is often
      # called the "Consul Template template". This option is required if not using
      # the `contents` option.
      source = "#{consul_template_template_path}/#{rabbitmq_config_template_file}"

      # This is the destination path on disk where the source template will render.
      # If the parent directories do not exist, Consul Template will attempt to
      # create them, unless create_dest_dirs is false.
      destination = "#{rabbitmq_config_file}"

      # This options tells Consul Template to create the parent directories of the
      # destination path if they do not exist. The default value is true.
      create_dest_dirs = false

      # This is the optional command to run when the template is rendered. The
      # command will only run if the resulting template changes. The command must
      # return within 30s (configurable), and it must have a successful exit code.
      # Consul Template is not a replacement for a process monitor or init system.
      command = "rabbitmqctl stop_app && rabbitmqctl reset && rabbitmqctl start_app"

      # This is the maximum amount of time to wait for the optional command to
      # return. Default is 30s.
      command_timeout = "15s"

      # Exit with an error when accessing a struct or map field/key that does not
      # exist. The default behavior will print "<no value>" when accessing a field
      # that does not exist. It is highly recommended you set this to "true" when
      # retrieving secrets from Vault.
      error_on_missing_key = false

      # This is the permission to render the file. If this option is left
      # unspecified, Consul Template will attempt to match the permissions of the
      # file that already exists at the destination path. If no file exists at that
      # path, the permissions are 0644.
      perms = 0755

      # This option backs up the previously rendered template at the destination
      # path before writing a new one. It keeps exactly one backup. This option is
      # useful for preventing accidental changes to the data without having a
      # rollback strategy.
      backup = true

      # These are the delimiters to use in the template. The default is "{{" and
      # "}}", but for some templates, it may be easier to use a different delimiter
      # that does not conflict with the output file itself.
      left_delimiter  = "{{"
      right_delimiter = "}}"

      # This is the `minimum(:maximum)` to wait before rendering a new template to
      # disk and triggering a command, separated by a colon (`:`). If the optional
      # maximum value is omitted, it is assumed to be 4x the required minimum value.
      # This is a numeric time with a unit suffix ("5s"). There is no default value.
      # The wait value for a template takes precedence over any globally-configured
      # wait.
      wait {
        min = "2s"
        max = "10s"
      }
    }
  HCL
  mode '755'
end
