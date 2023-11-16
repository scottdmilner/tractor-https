#!/bin/sh

set -x

entrypoint_log() {
    if [ -z "${NGINX_ENTRYPOINT_QUIET_LOGS:-}" ]; then
        echo "$@"
    fi
}

ME=$(basename "$0")

# install iptables 
# (NOTE: host kernel must have the following  modules enabled (via `modprobe`): iptable_mangle x_tables xt_mark)
apk add --no-cache iptables

# route all incoming traffic to default to the loopback device
ip rule del fwmark 1 lookup 100 2>/dev/null
ip rule add fwmark 1 lookup 100
ip route replace local 0.0.0.0/0 dev lo table 100

# route all captured TCP traffic on port 80 to engine
iptables -t mangle -D PREROUTING -p tcp -s engine --sport 8080 -j MARK --set-xmark 0x1/0xffffffff 2>/dev/null
iptables -t mangle -A PREROUTING -p tcp -s engine --sport 8080 -j MARK --set-xmark 0x1/0xffffffff

# allow engine to reach the external network
iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

entrypoint_log "$ME: info: Custom routing set up"

exit 0
