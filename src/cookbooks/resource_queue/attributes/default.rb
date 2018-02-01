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
default['erlang']['esl']['version'] = '20.1.7'

default['erlang']['consul_template_erlang_cookie'] = 'erlang_cookie.ctmpl'
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

default['rabbitmq']['version'] = '3.7.3'
default['rabbitmq']['mnesiadir'] = '/srv/rabbitmq/data/mnesia'


default['rabbitmq']['vhosts']['health'] = 'health'
default['rabbitmq']['vhosts']['logs'] = 'logs'

default['rabbitmq']['virtualhosts'] = [
  default['rabbitmq']['vhosts']['health'],
  default['rabbitmq']['vhosts']['logs']
]

default['rabbitmq']['users']['guest']['name'] = 'guest'
default['rabbitmq']['users']['guest']['password'] = 'guest'
default['rabbitmq']['users']['consul']['name'] = 'consul'
default['rabbitmq']['users']['consul']['password'] = 'consul'

default['rabbitmq']['enabled_users'] = [
  {
    name: default['rabbitmq']['users']['guest']['name'],
    password: default['rabbitmq']['users']['guest']['password'],
    rights: [
      {
        vhost: nil,
        conf: '.*',
        write: '.*',
        read: '.*'
      }
    ]
  },
  {
    name: default['rabbitmq']['users']['consul']['name'],
    password: default['rabbitmq']['users']['consul']['password'],
    rights: [
      {
        vhost: 'health',
        conf: '.*',
        write: '.*',
        read: '.*'
      }
    ]
  }
]

# loopback_users
# List of users which are only permitted to connect to the broker via a loopback interface (i.e. localhost).
# If you wish to allow the default guest user to connect remotely, you need to change this to [].
default['rabbitmq']['loopback_users'] = [
  default['rabbitmq']['users']['guest']['name'],
  default['rabbitmq']['users']['consul']['name']
]

default['rabbitmq']['amqp_port'] = 5672
default['rabbitmq']['http_port'] = 15_672

default['rabbitmq']['service_user'] = 'rabbitmq'
default['rabbitmq']['service_group'] = 'rabbitmq'

default['rabbitmq']['proxy_path'] = '/services/queue'

default['rabbitmq']['consul_template_cluster_file'] = 'rabbitmq_cluster.ctmpl'
default['rabbitmq']['script_cluster_file'] = '/tmp/rabbitmq_cluster.sh'

default['rabbitmq']['consul_template_config_file'] = 'rabbitmq_config.ctmpl'
default['rabbitmq']['config_file'] = '/etc/rabbitmq/rabbitmq.config'
