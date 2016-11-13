#!/usr/bin/env bash
set -euv -o pipefail

sudo ip route add 10.0.0.0/24 via 10.10.0.2 || true

cd "$( dirname "$0" )"

#vagrant destroy -f
vagrant up

# Try to reach the dashboard
curl -sSL 10.0.0.3 | grep -q "Kubernetes Dashboard"

vagrant ssh -c "kubectl run test --rm --image=alpine:3.4 -i --restart=Never -- sh -c 'set -euv; grep -q 10.0.0.10 /etc/resolv.conf; nslookup dashboard.kube-system | grep 10.0.0.3; nslookup kubernetes | grep 10.0.0.1'"
