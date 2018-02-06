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

    it 'creates and mounts the data file system at /srv/rabbitmq/dbase' do
      expect(chef_run).to create_directory('/srv/rabbitmq/dbase').with(
        group: 'rabbitmq',
        mode: '775',
        owner: 'rabbitmq'
      )
    end

    it 'creates and mounts the data file system at /srv/rabbitmq/dbase/mnesia' do
      expect(chef_run).to create_directory('/srv/rabbitmq/dbase/mnesia').with(
        group: 'rabbitmq',
        mode: '775',
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
  end

  context 'adds the consul-template files for rabbitmq' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    rabbitmq_cluster_template_content = <<~CONF
      #!/bin/sh

      rabbitmqctl set_cluster_name queue@{{ keyOrDefault "config/services/consul/datacenter" "consul" }}
    CONF
    it 'creates rabbitmq cluster template file in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/templates/rabbitmq_cluster.ctmpl')
        .with_content(rabbitmq_cluster_template_content)
    end

    consul_template_rabbitmq_cluster_content = <<~CONF
      # This block defines the configuration for a template. Unlike other blocks,
      # this block may be specified multiple times to configure multiple templates.
      # It is also possible to configure templates via the CLI directly.
      template {
        # This is the source file on disk to use as the input template. This is often
        # called the "Consul Template template". This option is required if not using
        # the `contents` option.
        source = "/etc/consul-template.d/templates/rabbitmq_cluster.ctmpl"

        # This is the destination path on disk where the source template will render.
        # If the parent directories do not exist, Consul Template will attempt to
        # create them, unless create_dest_dirs is false.
        destination = "/tmp/rabbitmq_cluster.sh"

        # This options tells Consul Template to create the parent directories of the
        # destination path if they do not exist. The default value is true.
        create_dest_dirs = false

        # This is the optional command to run when the template is rendered. The
        # command will only run if the resulting template changes. The command must
        # return within 30s (configurable), and it must have a successful exit code.
        # Consul Template is not a replacement for a process monitor or init system.
        command = "sh /tmp/rabbitmq_cluster.sh"

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
    CONF
    it 'creates rabbitmq_cluster.hcl in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/conf/rabbitmq_cluster.hcl')
        .with_content(consul_template_rabbitmq_cluster_content)
    end

    rabbitmq_config_template_content = <<~CONF
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
    it 'creates rabbitmq config template file in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/templates/rabbitmq_config.ctmpl')
        .with_content(rabbitmq_config_template_content)
    end

    consul_template_rabbitmq_config_content = <<~CONF
      # This block defines the configuration for a template. Unlike other blocks,
      # this block may be specified multiple times to configure multiple templates.
      # It is also possible to configure templates via the CLI directly.
      template {
        # This is the source file on disk to use as the input template. This is often
        # called the "Consul Template template". This option is required if not using
        # the `contents` option.
        source = "/etc/consul-template.d/templates/rabbitmq_config.ctmpl"

        # This is the destination path on disk where the source template will render.
        # If the parent directories do not exist, Consul Template will attempt to
        # create them, unless create_dest_dirs is false.
        destination = "/etc/rabbitmq/rabbitmq.config"

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
    CONF
    it 'creates rabbitmq_config.hcl in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/conf/rabbitmq_config.hcl')
        .with_content(consul_template_rabbitmq_config_content)
    end
  end
end
