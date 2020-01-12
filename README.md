# resource.queue

This repository contains the source code for the resource.queue image, the image that contains an
instance of the [RabbitMQ message broker](https://www.rabbitmq.com/).

## Image

The image is created by using the [Linux base image](https://github.com/Calvinverse/base.linux)
and amending it using a [Chef](https://www.chef.io/chef/) cookbook which installs
[Erlang](https://www.erlang.org/) and RabbitMQ.

When the image is created an extra virtual hard drive, called `rabbitmq_data.vhdx` is attached on
which the RabbitMQ data will be stored. This disk is mounted at the `/srv/rabbitmq` path

NOTE: The disk is attached by using a powershell command so that we can attach the disk and then go
find it and set the drive assignment to the unique  signature of the disk. When we deploy the VM we
only use the disks and create a new VM with those disks but that might lead to a different order in
which disks are attached. By having the drive assignments linked to the drive signature we prevent
issues with missing drives

### Contents

In addition to the default applications installed in the template image the following items are
also installed and configured:

* The Erlang runtime. The version of which is determined by the
  `default['erlang']['esl']['version']` attribute in the `default.rb` attributes file in the
  cookbook.
* The RabbitMQ application. The version of which is determined by the
  `default['rabbitmq']['version']` attribute in the `default.rb` attributes file in the cookbook.
* The RabbitMQ Database is configured to be on a separate disk which is mounted at `/srv/rabbitmq`
  during the build process.
* In addition to the RabbitMQ application the following plugins are installed and configured
  * The [management](https://www.rabbitmq.com/management.html) plugin which provides an HTTP based
    API for management and monitoring. This capability is used both so that users can easily
    determine the current state of the RabbitMQ cluster and make changes if necessary and so that
    [Telegraf](https://www.influxdata.com/time-series-platform/telegraf/) can collect metrics about
    the state of the cluster.
  * The [Consul](https://www.rabbitmq.com/cluster-formation.html#peer-discovery-consul) peer
    discovery plugin which provides means to discover other RabbitMQ instances in the environment.
  * The [LDAP](https://www.rabbitmq.com/ldap.html) plugin which allows authenticating users against
    LDAP and Active Directory.

### Configuration

The configuration for the RabbitMQ instance comes from a
[Consul-Template](https://github.com/hashicorp/consul-template) template file which replaces some
of the template parameters with values from the Consul Key-Value store.

Important parts of the configuration file are

* The default vhost is set to be `vhost.health`, which is the vhost that the HTTP health check
  for Consul will be using once it is configured.
* The default user is `guest` with the standard password. This user is only allowed to connect from
  the localhost and only has access to the `vhost.health` virtual host.
* Logs are streamed to the console, which is then send to syslog via systemd.
* Authentication is done either via the RabbitMQ build-in authentication store or via LDAP. In
  general users will authenticate via LDAP while services will authenticate via credentials stored
  in the build-in credential store.
* Cluster formation is done via the consul peer discovery plugin.

The RabbitMQ instance has no vhosts, queues, exchanges or users defined by default in the image. It
is assumed that these will either be configured through other processes, or by obtaining them from
other RabbitMQ instances in the environment when clustering happens.

The cluster name is set once RabbitMQ has been activated and is set to `rabbit@<CONSUL_ENVIRONMENT_NAME>`

Several services are added to [Consul](https://consul.io) for RabbitMQ. These are:

* Service: Queue - Tags: http - Port: 15672
* Service: Queue - Tags: mqtt - Port: 1883
* Service: Queue - Tags: amqp - Port: 5672

The first service also adds instructions for the [Fabio](https://github.com/fabiolb/fabio) load
balancer so that the RabbitMQ Management UI is available via the proxy.
The latter two point to the [MQTT](https://www.rabbitmq.com/mqtt.html) and
[AMQP](https://www.rabbitmq.com/tutorials/amqp-concepts.html) protocols respectively. The former
service is added through a consul configuration file while the latter is added by the RabbitMQ
peer-discovery plugin for consul. This is also the plugin that allows RabbitMQ to discover other
RabbitMQ instances in the environment for clustering purposes.

### Authentication

In order to interact with RabbitMQ both users and services need to be authenticated.
The authentication process depends on the entity doing the authentication.

Physical users are authenticated with Active Directory via the LDAP plugin which uses the following
settings.

Setting | Consul Key-Value path | Example
--------|-----------------------|---------
Active directory servers | `config/environment/directory/endpoints/hosts` | ad01.example.com, ad02.example.com
User Distinguished Name (DN) pattern | `${username}@{{ key "config/environment/mail/suffix" }}` | ${username}@example.com
DN lookup attribute | `userPrincipalName` | -
DN lookup base | `/config/environment/directory/query/users/lookupbase` | `OU=Users,DC=ad,DC=example,DC=com`
Group lookup base | `/config/environment/directory/query/groups/lookupbase` | `OU=Security Groups,OU=Builds,DC=ad,DC=example,DC=com`
Virtual host access query | `config/environment/directory/query/groups/queue/administrators` | `CN=Queue Administrator,OU=Groups,DC=ad,DC=example,DC=com`
Administrator group | `config/environment/directory/query/groups/queue/administrators` | `CN=Queue Administrators,OU=Groups,DC=ad,DC=example,DC=com`

It should be noted that currently only the administrator group is allowed to authenticate with
RabbitMQ.

Services authenticate via the built-in authentication store. Username and password combinations
are generated via [Vault](https://vaultproject.io).

### Clustering

The RabbitMQ instance in the image is able to cluster with other RabbitMQ instances in the Consul
environment it is connected to via the Consul peer discovery plugin.

When the RabbitMQ instance starts up it will determine if a database exists, which is removed on
first boot. If no database exists Rabbit will connect to Consul and try to discover other services
with a specific service name (`queue`) and tag (`amqp`). If at least one other service is found then
the RabbitMQ instance will try to cluster with this discovered service.

If no services are discovered with the provided service name and tag then the RabbitMQ instance will
initialize itself and establish itself with Consul for new RabbitMQ instances to discover. In doing
so it will register two services with Consul. The first being the `amqp.queue` service which
points to the [AMQP](https://www.rabbitmq.com/tutorials/amqp-concepts.html) port (`5672`).
The second service is the `http.queue` service which points to the
[HTTP management](https://www.rabbitmq.com/management.html) port (`15672`).

### Provisioning

No changes to the provisioning are applied other than the default one for the base image.

### Logs

No additional configuration is applied other than the default one for the base image.

### Metrics

Metrics are collected from the RabbitMQ cluster via [Telegraf](https://www.influxdata.com/time-series-platform/telegraf/).
In this first version of the image Telegraf assumes that there is a user with username `user.metrics` and
password `metrics` in the RabbitMQ database. At a later stage this user will be generated via
[Vault](https://vaultproject.io).

## Build, test and release

The build process follows the standard procedure for
[building Calvinverse images](https://www.calvinverse.net/documentation/how-to-build).

## Deploy

* Download the new image to one of your Hyper-V hosts.
* Create a directory for the image and copy the image VHDX file there.
* Create a VM that points to the image VHDX file with the following settings
  * Generation: 2
  * RAM: at least 1024 Mb
  * Hard disk: Use existing. Copy the path to the VHDX file
  * Attach the VM to a suitable network
* Update the VM settings:
  * Enable secure boot. Use the Microsoft UEFI Certificate Authority
  * Attach a DVD image that points to an ISO file containing the settings for the environment. These
    are normally found in the output of the [Calvinverse.Infrastructure](https://github.com/Calvinverse/calvinverse.infrastructure)
    repository. Pick the correct ISO for the task, in this case the `Linux Consul Client` image
  * Disable checkpoints
  * Set the VM to always start
  * Set the VM to shut down on stop
* Start the VM, it should automatically connect to the correct environment once it has provisioned
* In the RabbitMQ UI verify that the new host has connected and all queues have synchronised
* SSH into the first host (the one with the lowest IP address) and give the following command:
  `sudo rabbitmqctl stop`
* SSH into another rabbit node (doesn't matter which one as long as it's different from the first one)
  and issue the command: `rabbitmqctl forget_cluster_node rabbit@<ORIGINAL_NODE_NAME>`. In the UI
  confirm that the original node has been removed.
* From the original node issue the following commands to remove it from the environment
  * `consul leave`
  * `sudo shutdown now`
  * Wait for the node to shut down
* Once the VM has been shutdown it can be deleted and replaced with a new VM based on the new
  image.
* Repeat until all old instances have been replaced with new instances

## Usage

The Rabbit Management UI webpage will be made available from the proxy at the `/services/queue` sub-address.
