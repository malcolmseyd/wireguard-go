# copy these into your .bashrc or whatever
netns0="wg-test-0"
netns1="wg-test-1"
netns2="wg-test-2"

n0() { ip netns exec $netns0 "$@"; }
n1() { ip netns exec $netns1 "$@"; }
n2() { ip netns exec $netns2 "$@"; }
ip0() { ip -n $netns0 "$@"; }
ip1() { ip -n $netns1 "$@"; }
ip2() { ip -n $netns2 "$@"; }