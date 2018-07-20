# frozen_string_literal: true

#
# CONSULTEMPLATE
#

default['consul_template']['config_path'] = '/etc/consul-template.d/conf'
default['consul_template']['template_path'] = '/etc/consul-template.d/templates'

#
# ERLANG
#

default['erlang']['install_method'] = 'esl'
default['erlang']['esl']['version'] = '1:20.2.2'

default['erlang']['erlang_cookie'] = '/var/lib/rabbitmq/.erlang.cookie'

#
# FIREWALL
#

# Allow communication on the loopback address (127.0.0.1 and ::1)
default['firewall']['allow_loopback'] = true

# Do not allow MOSH connections
default['firewall']['allow_mosh'] = false

# Do not allow WinRM (which wouldn't work on Linux anyway, but close the ports just to be sure)
default['firewall']['allow_winrm'] = false

# No communication via IPv6 at all
default['firewall']['ipv6_enabled'] = false

#
# RABBITMQ
#

rabbitmq_version = '3.7.7'
default['rabbitmq']['version'] = rabbitmq_version

# For some reason the rabbitmq cookbook doesn't do the right thing, eventhough it should
default['rabbitmq']['deb_package'] = "rabbitmq-server_#{rabbitmq_version}-1_all.deb"
default['rabbitmq']['deb_package_url'] = "https://dl.bintray.com/rabbitmq/all/rabbitmq-server/#{rabbitmq_version}/"

default['rabbitmq']['service_data_path'] = '/srv/rabbitmq/dbase'
default['rabbitmq']['mnesiadir'] = "#{node['rabbitmq']['service_data_path']}/mnesia"

# plugins
default['rabbitmq']['enabled_plugins'] = %w[
  rabbitmq_management
  rabbitmq_auth_backend_ldap
  rabbitmq_peer_discovery_consul
  rabbitmq_mqtt
]
default['rabbitmq']['disabled_plugins'] = %w[
  rabbitmq_management_visualiser
]

default['rabbitmq']['vhosts']['health'] = 'vhost.health'

default['rabbitmq']['amqp_port'] = 5672
default['rabbitmq']['http_port'] = 15_672
default['rabbitmq']['mqtt_port'] = 1883

default['rabbitmq']['service_user'] = 'rabbitmq'
default['rabbitmq']['service_group'] = 'rabbitmq'

default['rabbitmq']['proxy_path'] = '/services/queue'

default['rabbitmq']['consul_template_config_script_file'] = 'rabbitmq_config_script.ctmpl'
default['rabbitmq']['script_config_file'] = '/tmp/rabbitmq_config.sh'

default['rabbitmq']['config_file'] = '/etc/rabbitmq/rabbitmq.config'

default['rabbitmq']['telegraf']['consul_template_inputs_file'] = 'telegraf_rabbitmq_inputs.ctmpl'

#
# TELEGRAF
#

default['telegraf']['config_directory'] = '/etc/telegraf/telegraf.d'
