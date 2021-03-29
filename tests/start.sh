#!/bin/bash

set -e

exec 3>&1
export WG_HIDE_KEYS=never
netns0="ns0"
netns1="ns1"
netns2="ns2"
netns3="ns3"
program=$1
# export LOG_LEVEL="verbose"

pretty() { echo -e "\x1b[32m\x1b[1m[+] ${1:+NS$1: }${2}\x1b[0m" >&3; }
pp() { pretty "" "$*"; "$@"; }
maybe_exec() { if [[ $BASHPID -eq $$ ]]; then "$@"; else exec "$@"; fi; }
n0() { pretty 0 "$*"; maybe_exec ip netns exec $netns0 "$@"; }
n1() { pretty 1 "$*"; maybe_exec ip netns exec $netns1 "$@"; }
n2() { pretty 2 "$*"; maybe_exec ip netns exec $netns2 "$@"; }
n3() { pretty 3 "$*"; maybe_exec ip netns exec $netns3 "$@"; }
ip0() { pretty 0 "ip $*"; ip -n $netns0 "$@"; }
ip1() { pretty 1 "ip $*"; ip -n $netns1 "$@"; }
ip2() { pretty 2 "ip $*"; ip -n $netns2 "$@"; }
ip3() { pretty 3 "ip $*"; ip -n $netns3 "$@"; }
sleep() { read -t "$1" -N 0 || true; }
waitiperf() { pretty "${1//*-}" "wait for iperf:5201"; while [[ $(ss -N "$1" -tlp 'sport = 5201') != *iperf3* ]]; do sleep 0.1; done; }
waitncatudp() { pretty "${1//*-}" "wait for udp:1111"; while [[ $(ss -N "$1" -ulp 'sport = 1111') != *ncat* ]]; do sleep 0.1; done; }
waitiface() { pretty "${1//*-}" "wait for $2 to come up"; ip netns exec "$1" bash -c "while [[ \$(< \"/sys/class/net/$2/operstate\") != up ]]; do read -t .1 -N 0 || true; done;"; }

cleanup() {
    echo ">>> Cleaning up!"
    set +e
    exec 2>/dev/null
    printf "$orig_message_cost" > /proc/sys/net/core/message_cost
    ip0 link del dev wg1
    ip1 link del dev wg1
    ip2 link del dev wg1
    ip3 link del dev wg1
    local to_kill="$(ip netns pids $netns0) $(ip netns pids $netns1) $(ip netns pids $netns2) $(ip netns pids $netns3)"
    [[ -n $to_kill ]] && kill $to_kill
    pp ip netns del $netns1
    pp ip netns del $netns2
    pp ip netns del $netns3
    pp ip netns del $netns0
    exit
}

noop() { echo; }

orig_message_cost="$(< /proc/sys/net/core/message_cost)"
trap cleanup EXIT
printf 0 > /proc/sys/net/core/message_cost

ip netns del $netns0 2>/dev/null || true
ip netns del $netns1 2>/dev/null || true
ip netns del $netns2 2>/dev/null || true
ip netns del $netns3 2>/dev/null || true
pp ip netns add $netns0
pp ip netns add $netns1
pp ip netns add $netns2
pp ip netns add $netns3
ip0 link set up dev lo

# ip0 link add dev wg1 type wireguard
n0 $program wg1
ip0 link set wg1 netns $netns1

# ip0 link add dev wg2 type wireguard
n0 $program wg2
ip0 link set wg2 netns $netns2

# ip0 link add dev wg3 type wireguard
n0 $program wg3
ip0 link set wg3 netns $netns3

key1="$(pp wg genkey)"
key2="$(pp wg genkey)"
key3="$(pp wg genkey)"
pub1="$(pp wg pubkey <<<"$key1")"
pub2="$(pp wg pubkey <<<"$key2")"
pub3="$(pp wg pubkey <<<"$key3")"
psk="$(pp wg genpsk)"
[[ -n $key1 && -n $key2 && -n $key3 && -n $psk ]]

configure_peers() {

    ip1 addr add 192.168.241.1/24 dev wg1
    ip1 addr add fd00::1/24 dev wg1

    ip2 addr add 192.168.241.2/24 dev wg2
    ip2 addr add fd00::2/24 dev wg2

    ip3 addr add 192.168.241.3/24 dev wg3
    ip3 addr add fd00::3/24 dev wg3

    n0 wg set wg1 \
        private-key <(echo "$key1") \
        listen-port 10000 \
        peer "$pub2" \
            preshared-key <(echo "$psk") \
            allowed-ips 192.168.241.2/32,fd00::2/128 \
        peer "$pub3" \
            preshared-key <(echo "$psk") \
            allowed-ips 192.168.241.3/32,fd00::3/128
    n0 wg set wg2 \
        private-key <(echo "$key2") \
        listen-port 20000 \
        peer "$pub1" \
            preshared-key <(echo "$psk") \
            allowed-ips 192.168.241.1/32,fd00::1/128 \
        peer "$pub3" \
            preshared-key <(echo "$psk") \
            allowed-ips 192.168.241.3/32,fd00::3/128
    n0 wg set wg3 \
        private-key <(echo "$key3") \
        listen-port 30000 \
        peer "$pub2" \
            preshared-key <(echo "$psk") \
            allowed-ips 192.168.241.2/32,fd00::2/128 \
        peer "$pub1" \
            preshared-key <(echo "$psk") \
            allowed-ips 192.168.241.1/32,fd00::1/128

    n0 wg showconf wg1
    n0 wg showconf wg2
    n0 wg showconf wg3

    ip1 link set up dev wg1
    ip2 link set up dev wg2
    ip3 link set up dev wg3
    sleep 1
}
configure_peers

tests() {
    # Ping over IPv4
    n2 ping -c 10 -f -W 1 192.168.241.1
    n1 ping -c 10 -f -W 1 192.168.241.2
}

# Test using IPv4 as outer transport
#n0 wg set wg1 peer "$pub2" endpoint 127.0.0.1:20000
#n0 wg set wg2 peer "$pub1" endpoint 127.0.0.1:10000

# Before calling tests, we first make sure that the stats counters are working
#n2 ping -c 10 -f -W 1 192.168.241.1
#{ read _; read _; read _; read rx_bytes _; read _; read tx_bytes _; } < <(ip2 -stats link show dev wg2)
#ip2 -stats link show dev wg2
#n0 wg show
#[[ $rx_bytes -ge 840 && $tx_bytes -ge 880 && $rx_bytes -lt 2500 && $rx_bytes -lt 2500 ]]
#echo "counters working"
#
#tests

trap noop EXIT
