# frozen_string_literal: true

#
# CONSULTEMPLATE
#

default['consul_template']['config_path'] = '/etc/consul-template.d/conf'
default['consul_template']['template_path'] = '/etc/consul-template.d/templates'

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

default['rabbitmq']['version'] = '3.6.15'

default['rabbitmq']['amqp_port'] = 5672
default['rabbitmq']['http_port'] = 15_672

default['rabbitmq']['service_user'] = 'rabbitmq'
default['rabbitmq']['service_group'] = 'rabbitmq'

default['rabbitmq']['proxy_path'] = '/services/queue'

default['rabbitmq']['consul_template_cluster_file'] = 'rabbitmq_cluster.ctmpl'
default['rabbitmq']['script_cluster_file'] = '/tmp/rabbitmq_cluster.sh'
