# copy these into your .bashrc or whatever
netns0="ns0"
netns1="ns1"
netns2="ns2"
netns3="ns2"

n0() { ip netns exec $netns0 "$@"; }
n1() { ip netns exec $netns1 "$@"; }
n2() { ip netns exec $netns2 "$@"; }
n3() { ip netns exec $netns3 "$@"; }
ip0() { ip -n $netns0 "$@"; }
ip1() { ip -n $netns1 "$@"; }
ip2() { ip -n $netns2 "$@"; }
ip3() { ip -n $netns3 "$@"; }