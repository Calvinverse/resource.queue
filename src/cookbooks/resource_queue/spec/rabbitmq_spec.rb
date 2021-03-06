# frozen_string_literal: true

require 'spec_helper'

describe 'resource_queue::rabbitmq' do
  context 'installs RabbitMQ' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'installs the RabbitMQ service' do
      expect(chef_run).to include_recipe('rabbitmq::default')
      expect(chef_run).to include_recipe('rabbitmq::plugin_management')
      expect(chef_run).to include_recipe('rabbitmq::user_management')
      expect(chef_run).to include_recipe('rabbitmq::virtualhost_management')
    end

    it 'disables the rabbitmq service' do
      expect(chef_run).to disable_service('rabbitmq-server')
    end

    it 'creates and mounts the data file system at /srv/rabbitmq/dbase' do
      expect(chef_run).to create_directory('/srv/rabbitmq/dbase').with(
        group: 'rabbitmq',
        mode: '750',
        owner: 'rabbitmq'
      )
    end

    it 'creates and mounts the data file system at /srv/rabbitmq/dbase/mnesia' do
      expect(chef_run).to create_directory('/srv/rabbitmq/dbase/mnesia').with(
        group: 'rabbitmq',
        mode: '750',
        owner: 'rabbitmq'
      )
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

    it 'opens the RabbitMQ MQTT port' do
      expect(chef_run).to create_firewall_rule('rabbitmq-mqtt').with(
        command: :allow,
        dest_port: 1883,
        direction: :in
      )
    end

    it 'opens the RabbitMQ peer discovery port' do
      expect(chef_run).to create_firewall_rule('rabbitmq-peer-discovery').with(
        command: :allow,
        dest_port: 4369,
        direction: :in
      )
    end

    it 'opens the RabbitMQ Erlang internode traffic port' do
      expect(chef_run).to create_firewall_rule('rabbitmq-erlang-internode').with(
        command: :allow,
        dest_port: 25_672,
        direction: :in
      )
    end
  end

  context 'registers the http service with consul' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    consul_rabbitmq_config_content = <<~JSON
      {
        "services": [
          {
            "checks": [
              {
                "header": { "Authorization" : ["Basic dXNlci5oZWFsdGg6aGVhbHRo"]},
                "http": "http://localhost:15672/api/aliveness-test/vhost.health",
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
            "port": 15672,
            "tags": [
              "edgeproxyprefix-/services/queue strip=/services/queue",
              "http"
            ]
          }
        ]
      }
    JSON
    it 'creates the /etc/consul/conf.d/rabbitmq-http.json' do
      expect(chef_run).to create_file('/etc/consul/conf.d/rabbitmq-http.json')
        .with_content(consul_rabbitmq_config_content)
    end

    consul_rabbitmq_mqtt_content = <<~JSON
      {
        "services": [
          {
            "checks": [
              {
                "header": { "Authorization" : ["Basic dXNlci5oZWFsdGg6aGVhbHRo"]},
                "http": "http://localhost:15672/api/aliveness-test/vhost.health",
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
            "port": 1883,
            "tags": [
              "mqtt"
            ]
          }
        ]
      }
    JSON
    it 'creates the /etc/consul/conf.d/rabbitmq-mqtt.json' do
      expect(chef_run).to create_file('/etc/consul/conf.d/rabbitmq-mqtt.json')
        .with_content(consul_rabbitmq_mqtt_content)
    end
  end

  context 'adds the consul-template files for rabbitmq' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    rabbitmq_config_script_template_content = <<~CONF
      #!/bin/sh

      {{ if keyExists "config/services/consul/datacenter" }}
      {{ if keyExists "config/services/consul/domain" }}
      echo 'Write the erlang cookie file ...'
      cat <<'EOT' > /var/lib/rabbitmq/.erlang.cookie
      queue@{{ key "config/services/consul/datacenter" }}
      EOT

      echo 'Write the rabbitmq configuration file'
      cat <<'EOT' > /etc/rabbitmq/rabbitmq.config
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
                  port, 15672
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

      chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
      if ( ! $(systemctl is-enabled --quiet rabbitmq-server) ); then
        if [ -f /var/lib/rabbitmq/mnesia ]; then
          rm -rf /var/lib/rabbitmq/mnesia
        fi

        if [ -f /srv/rabbitmq/dbase/mnesia ]; then
          rm -rf /srv/rabbitmq/dbase/mnesia
        fi

        systemctl enable rabbitmq-server

        while true; do
          if ( $(systemctl is-enabled --quiet rabbitmq-server) ); then
              break
          fi

          sleep 1
        done
      fi

      systemctl restart rabbitmq-server && rabbitmqctl set_cluster_name queue@{{ key "config/services/consul/datacenter" }}

      while true; do
        if ( $(systemctl is-active --quiet rabbitmq-server) ); then
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
    it 'creates rabbitmq config script template file in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/templates/rabbitmq_config_script.ctmpl')
        .with_content(rabbitmq_config_script_template_content)
        .with(
          group: 'root',
          owner: 'root',
          mode: '0550'
        )
    end

    consul_template_rabbitmq_config_content = <<~CONF
      # This block defines the configuration for a template. Unlike other blocks,
      # this block may be specified multiple times to configure multiple templates.
      # It is also possible to configure templates via the CLI directly.
      template {
        # This is the source file on disk to use as the input template. This is often
        # called the "Consul Template template". This option is required if not using
        # the `contents` option.
        source = "/etc/consul-template.d/templates/rabbitmq_config_script.ctmpl"

        # This is the destination path on disk where the source template will render.
        # If the parent directories do not exist, Consul Template will attempt to
        # create them, unless create_dest_dirs is false.
        destination = "/tmp/rabbitmq_config.sh"

        # This options tells Consul Template to create the parent directories of the
        # destination path if they do not exist. The default value is true.
        create_dest_dirs = false

        # This is the optional command to run when the template is rendered. The
        # command will only run if the resulting template changes. The command must
        # return within 30s (configurable), and it must have a successful exit code.
        # Consul Template is not a replacement for a process monitor or init system.
        command = "sh /tmp/rabbitmq_config.sh"

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
    CONF
    it 'creates rabbitmq_config.hcl in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/conf/rabbitmq_config.hcl')
        .with_content(consul_template_rabbitmq_config_content)
        .with(
          group: 'root',
          owner: 'root',
          mode: '0550'
        )
    end
  end

  context 'adds the consul-template files for telegraf monitoring of rabbitmq' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    telegraf_rabbit_inputs_template_content = <<~CONF
      # Telegraf Configuration

      ###############################################################################
      #                            INPUT PLUGINS                                    #
      ###############################################################################

      [[inputs.rabbitmq]]
        ## Management Plugin url. (default: http://localhost:15672)
        url = "http://localhost:15672"

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
    it 'creates telegraf rabbitmq input template file in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/templates/telegraf_rabbitmq_inputs.ctmpl')
        .with_content(telegraf_rabbit_inputs_template_content)
        .with(
          group: 'root',
          owner: 'root',
          mode: '0550'
        )
    end

    consul_template_telegraf_rabbit_inputs_content = <<~CONF
      # This block defines the configuration for a template. Unlike other blocks,
      # this block may be specified multiple times to configure multiple templates.
      # It is also possible to configure templates via the CLI directly.
      template {
        # This is the source file on disk to use as the input template. This is often
        # called the "Consul Template template". This option is required if not using
        # the `contents` option.
        source = "/etc/consul-template.d/templates/telegraf_rabbitmq_inputs.ctmpl"

        # This is the destination path on disk where the source template will render.
        # If the parent directories do not exist, Consul Template will attempt to
        # create them, unless create_dest_dirs is false.
        destination = "/etc/telegraf/telegraf.d/inputs_rabbitmq.conf"

        # This options tells Consul Template to create the parent directories of the
        # destination path if they do not exist. The default value is true.
        create_dest_dirs = false

        # This is the optional command to run when the template is rendered. The
        # command will only run if the resulting template changes. The command must
        # return within 30s (configurable), and it must have a successful exit code.
        # Consul Template is not a replacement for a process monitor or init system.
        command = "/bin/bash -c 'chown telegraf:telegraf /etc/telegraf/telegraf.d/inputs_rabbitmq.conf && systemctl restart telegraf'"

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
    CONF
    it 'creates telegraf_rabbitmq_inputs.hcl in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/conf/telegraf_rabbitmq_inputs.hcl')
        .with_content(consul_template_telegraf_rabbit_inputs_content)
        .with(
          group: 'root',
          owner: 'root',
          mode: '0550'
        )
    end
  end
end
