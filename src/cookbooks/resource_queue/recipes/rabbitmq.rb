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

# Make sure the rabbitmq service doesn't start automatically. This will be changed
# after we have provisioned the box
rabbit_service_name = node['rabbitmq']['service_name']
service rabbit_service_name do
  action :disable
end

#
# SET PERMISSIONS ON DATA PATH
#

rabbitmq_service_path = node['rabbitmq']['service_data_path']
directory rabbitmq_service_path do
  action :create
  group node['rabbitmq']['service_group']
  mode '750'
  owner node['rabbitmq']['service_user']
  recursive true
end

rabbitmq_mnesia_path = node['rabbitmq']['mnesiadir']
directory rabbitmq_mnesia_path do
  action :create
  group node['rabbitmq']['service_group']
  mode '750'
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

rabbitmq_mqtt_port = node['rabbitmq']['mqtt_port']
firewall_rule 'rabbitmq-mqtt' do
  command :allow
  description 'Allow RabbitMQ MQTT traffic'
  dest_port rabbitmq_mqtt_port
  direction :in
end

firewall_rule 'rabbitmq-peer-discovery' do
  command :allow
  description 'Allow RabbitMQ peer discovery traffic'
  dest_port 4369
  direction :in
end

firewall_rule 'rabbitmq-erlang-internode' do
  command :allow
  description 'Allow RabbitMQ Erlang internode traffic'
  dest_port rabbitmq_amqp_port + 20_000
  direction :in
end

#
# CONSUL FILES
#

# This assumes the health user is called 'user.health' and the password is 'health'
health_vhost = node['rabbitmq']['vhosts']['health']
proxy_path = node['rabbitmq']['proxy_path']
file '/etc/consul/conf.d/rabbitmq-http.json' do
  action :create
  content <<~JSON
    {
      "services": [
        {
          "checks": [
            {
              "header": { "Authorization" : ["Basic dXNlci5oZWFsdGg6aGVhbHRo"]},
              "http": "http://localhost:#{rabbitmq_http_port}/api/aliveness-test/#{health_vhost}",
              "id": "rabbitmq_http_health_check",
              "interval": "30s",
              "method": "GET",
              "name": "RabbitMQ HTTP health check",
              "timeout": "5s"
            }
          ],
          "enable_tag_override": false,
          "id": "rabbitmq_management",
          "name": "queue",
          "port": #{rabbitmq_http_port},
          "tags": [
            "edgeproxyprefix-#{proxy_path} strip=#{proxy_path}",
            "http"
          ]
        }
      ]
    }
  JSON
end

file '/etc/consul/conf.d/rabbitmq-mqtt.json' do
  action :create
  content <<~JSON
    {
      "services": [
        {
          "checks": [
            {
              "header": { "Authorization" : ["Basic dXNlci5oZWFsdGg6aGVhbHRo"]},
              "http": "http://localhost:#{rabbitmq_http_port}/api/aliveness-test/#{health_vhost}",
              "id": "rabbitmq_mqtt_health_check",
              "interval": "30s",
              "method": "GET",
              "name": "RabbitMQ MQTT health check",
              "timeout": "5s"
            }
          ],
          "enable_tag_override": false,
          "id": "rabbitmq_mqtt",
          "name": "queue",
          "port": #{rabbitmq_mqtt_port},
          "tags": [
            "mqtt"
          ]
        }
      ]
    }
  JSON
end

#
# CONSUL-TEMPLATE FILES
#

consul_template_config_path = node['consul_template']['config_path']
consul_template_template_path = node['consul_template']['template_path']

# There are several files that need to be rendered, all with similar information. Upon rendering
# each file technically RabbitMQ needs to be restarted. That leads to either race conditions
# or massive start-stop issues where rabbitmq is just restarted only to restart again half-way the
# process. This can lead to issues with the data stored by rabbit
# So the solution is to render a single script that creates all three files with the correct
# permissions

erlang_cookie_file = node['erlang']['erlang_cookie']
rabbitmq_config_file = node['rabbitmq']['config_file']

rabbitmq_user = node['rabbitmq']['service_user']
rabbitmq_group = node['rabbitmq']['service_group']

rabbitmq_config_script_template_file = node['rabbitmq']['consul_template_config_script_file']
file "#{consul_template_template_path}/#{rabbitmq_config_script_template_file}" do
  action :create
  content <<~CONF
    #!/bin/sh

    {{ if keyExists "config/services/consul/datacenter" }}
    {{ if keyExists "config/services/consul/domain" }}
    echo 'Write the erlang cookie file ...'
    cat <<'EOT' > #{erlang_cookie_file}
    queue@{{ key "config/services/consul/datacenter" }}
    EOT

    echo 'Write the rabbitmq configuration file'
    cat <<'EOT' > #{rabbitmq_config_file}
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
            cluster_partition_handling, autoheal
          },
          {
            default_pass, <<"guest">>
          },
          {
            default_user, <<"guest">>
          },
          {
            default_vhost, <<"vhost.health">>
          },
          {
            heartbeat, 60
          },
          {
            log, [
              {
                console, [
                  {enabled, true},
                  {level, info}
                ]
              }
            ]
          },
          {
            loopback_users, [
              <<"guest">>,
              <<"health">>,
              <<"metrics">>
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
          },
          {
            rabbitmq_mqtt, [
              {
                default_pass, <<"guest">>
              },
              {
                default_user, <<"guest">>
              },
              {
                exchange, <<"amq.topic">>
              },
              {
                vhost, <<"vhost.mqtt">>
              }
            ]
          },
          {
            cluster_formation, [
              {
                peer_discovery_backend, rabbit_peer_discovery_consul
              },
              {
                peer_discovery_consul, [
                  { consul_svc, "queue" },
                  { consul_svc_tags, ["amqp"] },
                  { consul_svc_addr_auto, false },
                  { consul_domain, "{{ keyOrDefault "config/services/consul/domain" "unknown" }}" },
                  { consul_lock_prefix, "data/services/queue" },
                  { consul_include_nodes_with_warnings, true }
                ]
              }
            ]
          }
        ]
    {{ if keyExists "config/environment/directory/initialized" }}
      },
      {
        rabbitmq_auth_backend_ldap, [
          {
            servers, [
              {{range $index, $service := ls "config/environment/directory/endpoints/hosts" }}{{if ne $index 0}},{{end}}"{{ .Value }}"{{end}}
            ]
          },
          {
            user_dn_pattern, "${username}@{{ key "config/environment/mail/suffix" }}"
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
            vhost_access_query, { in_group_nested, "{{ keyOrDefault "/config/environment/directory/query/groups/queue/administrators" "" }}" }
          },
          {
            tag_queries, [
              {
                administrator, { in_group_nested, "{{ keyOrDefault "/config/environment/directory/query/groups/queue/administrators" "" }}" }
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
    EOT

    chown #{rabbitmq_user}:#{rabbitmq_group} #{erlang_cookie_file}
    if ( ! $(systemctl is-enabled --quiet #{rabbit_service_name}) ); then
      if [ -f /var/lib/rabbitmq/mnesia ]; then
        rm -rf /var/lib/rabbitmq/mnesia
      fi

      if [ -f /srv/rabbitmq/dbase/mnesia ]; then
        rm -rf /srv/rabbitmq/dbase/mnesia
      fi

      systemctl enable #{rabbit_service_name}

      while true; do
        if ( $(systemctl is-enabled --quiet #{rabbit_service_name}) ); then
            break
        fi

        sleep 1
      done
    fi

    systemctl restart #{rabbit_service_name} && rabbitmqctl set_cluster_name queue@{{ key "config/services/consul/datacenter" }}

    while true; do
      if ( $(systemctl is-active --quiet #{rabbit_service_name}) ); then
          break
      fi

      sleep 1
    done

    {{ else }}
    echo 'Not all Consul K-V values are available. Will not start RabbitMQ.'
    {{ end }}
    {{ else }}
    echo 'Not all Consul K-V values are available. Will not start RabbitMQ.'
    {{ end }}
  CONF
  group 'root'
  mode '0550'
  owner 'root'
end

rabbitmq_config_script_file = node['rabbitmq']['script_config_file']
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
      source = "#{consul_template_template_path}/#{rabbitmq_config_script_template_file}"

      # This is the destination path on disk where the source template will render.
      # If the parent directories do not exist, Consul Template will attempt to
      # create them, unless create_dest_dirs is false.
      destination = "#{rabbitmq_config_script_file}"

      # This options tells Consul Template to create the parent directories of the
      # destination path if they do not exist. The default value is true.
      create_dest_dirs = false

      # This is the optional command to run when the template is rendered. The
      # command will only run if the resulting template changes. The command must
      # return within 30s (configurable), and it must have a successful exit code.
      # Consul Template is not a replacement for a process monitor or init system.
      command = "sh #{rabbitmq_config_script_file}"

      # This is the maximum amount of time to wait for the optional command to
      # return. Default is 30s.
      command_timeout = "60s"

      # Exit with an error when accessing a struct or map field/key that does not
      # exist. The default behavior will print "<no value>" when accessing a field
      # that does not exist. It is highly recommended you set this to "true" when
      # retrieving secrets from Vault.
      error_on_missing_key = false

      # This is the permission to render the file. If this option is left
      # unspecified, Consul Template will attempt to match the permissions of the
      # file that already exists at the destination path. If no file exists at that
      # path, the permissions are 0644.
      perms = 0550

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
  group 'root'
  mode '0550'
  owner 'root'
end

telegraf_service = 'telegraf'
telegraf_config_directory = node['telegraf']['config_directory']
telegraf_rabbitmq_inputs_template_file = node['rabbitmq']['telegraf']['consul_template_inputs_file']
file "#{consul_template_template_path}/#{telegraf_rabbitmq_inputs_template_file}" do
  action :create
  content <<~CONF
    # Telegraf Configuration

    ###############################################################################
    #                            INPUT PLUGINS                                    #
    ###############################################################################

    [[inputs.rabbitmq]]
      ## Management Plugin url. (default: http://localhost:15672)
      url = "http://localhost:#{rabbitmq_http_port}"

      ## Credentials
      username = "user.metrics"
      password = "metrics"

      ## Optional SSL Config
      # ssl_ca = "/etc/telegraf/ca.pem"
      # ssl_cert = "/etc/telegraf/cert.pem"
      # ssl_key = "/etc/telegraf/key.pem"
      ## Use SSL but skip chain & host verification
      # insecure_skip_verify = false

      ## Optional request timeouts
      ##
      ## ResponseHeaderTimeout, if non-zero, specifies the amount of time to wait
      ## for a server's response headers after fully writing the request.
      # header_timeout = "3s"
      ##
      ## client_timeout specifies a time limit for requests made by this client.
      ## Includes connection time, any redirects, and reading the response body.
      # client_timeout = "4s"

      ## A list of nodes to gather as the rabbitmq_node measurement. If not
      ## specified, metrics for all nodes are gathered.
      # nodes = ["rabbit@node1", "rabbit@node2"]

      ## A list of queues to gather as the rabbitmq_queue measurement. If not
      ## specified, metrics for all queues are gathered.
      # queues = ["telegraf"]
      [inputs.rabbitmq.tags]
        influxdb_database = "services"
  CONF
  group 'root'
  mode '0550'
  owner 'root'
end

file "#{consul_template_config_path}/telegraf_rabbitmq_inputs.hcl" do
  action :create
  content <<~HCL
    # This block defines the configuration for a template. Unlike other blocks,
    # this block may be specified multiple times to configure multiple templates.
    # It is also possible to configure templates via the CLI directly.
    template {
      # This is the source file on disk to use as the input template. This is often
      # called the "Consul Template template". This option is required if not using
      # the `contents` option.
      source = "#{consul_template_template_path}/#{telegraf_rabbitmq_inputs_template_file}"

      # This is the destination path on disk where the source template will render.
      # If the parent directories do not exist, Consul Template will attempt to
      # create them, unless create_dest_dirs is false.
      destination = "#{telegraf_config_directory}/inputs_rabbitmq.conf"

      # This options tells Consul Template to create the parent directories of the
      # destination path if they do not exist. The default value is true.
      create_dest_dirs = false

      # This is the optional command to run when the template is rendered. The
      # command will only run if the resulting template changes. The command must
      # return within 30s (configurable), and it must have a successful exit code.
      # Consul Template is not a replacement for a process monitor or init system.
      command = "/bin/bash -c 'chown #{node['telegraf']['service_user']}:#{node['telegraf']['service_group']} #{telegraf_config_directory}/inputs_rabbitmq.conf && systemctl restart #{telegraf_service}'"

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
      perms = 0550

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
  group 'root'
  mode '0550'
  owner 'root'
end
