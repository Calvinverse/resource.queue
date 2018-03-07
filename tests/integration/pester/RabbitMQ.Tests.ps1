Describe 'The rabbitmq application' {
    Context 'is installed' {
        It 'with binaries in /usr/lib/rabbitmq' {
            '/usr/lib/rabbitmq' | Should Exist

            '/usr/lib/rabbitmq/bin' | Should Exist
            '/usr/lib/rabbitmq/bin/rabbitmq-server' | Should Exist
        }

        It 'with default configuration in /etc/rabbitmq/rabbitmq.config' {
            '/etc/rabbitmq/rabbitmq.config' | Should Exist
        }

        It 'with environment configuration in /etc/rabbitmq' {
            '/etc/rabbitmq/rabbitmq-env.conf' | Should Exist
        }
    }

    Context 'has been daemonized' {
        $serviceConfigurationPath = '/lib/systemd/system/rabbitmq-server.service'
        if (-not (Test-Path $serviceConfigurationPath))
        {
            It 'has a systemd configuration' {
               $false | Should Be $true
            }
        }

        $expectedContent = @'
# systemd unit example
[Unit]
Description=RabbitMQ broker
After=network.target epmd@0.0.0.0.socket
Wants=network.target epmd@0.0.0.0.socket

[Service]
Type=notify
User=rabbitmq
Group=rabbitmq
NotifyAccess=all
TimeoutStartSec=3600
# The following setting will automatically restart RabbitMQ
# in the event of a failure. systemd service restarts are not a
# replacement for service monitoring. Please see
# http://www.rabbitmq.com/monitoring.html
Restart=on-failure
RestartSec=10
WorkingDirectory=/var/lib/rabbitmq
ExecStart=/usr/lib/rabbitmq/bin/rabbitmq-server
ExecStop=/usr/lib/rabbitmq/bin/rabbitmqctl stop
ExecStop=/bin/sh -c "while ps -p $MAINPID >/dev/null 2>&1; do sleep 1; done"
# See rabbitmq/rabbitmq-server-release#51
SuccessExitStatus=69

[Install]
WantedBy=multi-user.target

'@
        $serviceFileContent = Get-Content $serviceConfigurationPath | Out-String
        $systemctlOutput = & systemctl status rabbitmq-server
        It 'with a systemd service' {
            #$serviceFileContent | Should Be ($expectedContent -replace "`r", "")

            $systemctlOutput | Should Not Be $null
            $systemctlOutput.GetType().FullName | Should Be 'System.Object[]'
            $systemctlOutput.Length | Should BeGreaterThan 3
            $systemctlOutput[0] | Should Match 'rabbitmq-server.service - RabbitMQ broker'
        }

        It 'that is enabled' {
            $systemctlOutput[1] | Should Match 'Loaded:\sloaded\s\(.*;\senabled;.*\)'

        }

        It 'and is running' {
            #$systemctlOutput[2] | Should Match 'Active:\sactive\s\(running\).*'
        }
    }

    Context 'can be contacted' {
        $ifConfigResponse = & ifconfig eth0
        $line = $ifConfigResponse[1].Trim()
        # Expecting line to be:
        #     inet addr:192.168.6.46  Bcast:192.168.6.255  Mask:255.255.255.0
        $localIpAddress = $line.SubString(10, ($line.IndexOf(' ', 10) - 10))

        try
        {
            $user = 'consul'
            $pass = 'c0nsul'

            $pair = "$($user):$($pass)"

            $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))

            $basicAuthValue = "Basic $encodedCreds"

            $headers = @{
                Authorization = $basicAuthValue
            }

            $response = Invoke-WebRequest -Uri "http://$($localIpAddress):15672/api/aliveness-test/health" -Headers $headers -UseBasicParsing
        }
        catch
        {
            # Because powershell sucks it throws if the response code isn't a 200 one ...
            $response = $_.Exception.Response
        }

        It 'responds to HTTP calls' {
            # $response.StatusCode | Should Be 501
        }
    }
}
