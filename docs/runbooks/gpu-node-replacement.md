# GPU Node Replacement And Onboarding Runbook

## Purpose

This runbook documents the exact workflow used on `2026-03-25` to remove the dead GPU nodes `gpu-1` and `gpu-2` and add the replacement node `sxmgpu` (`89.108.125.7`, user `gputester`, `8x NVIDIA H200`) into the live cluster.

Use this file as the primary operational procedure when a future GPU node must be:

- added to the cluster
- replaced after host loss
- reintroduced when control-plane reachability exists only over public IPs

This document deliberately records:

- the commands that were run
- why each command was needed
- every failure encountered
- how each failure was diagnosed and resolved

Secrets are intentionally replaced with placeholders.

## Preconditions

You have:

- repository access on the operator machine
- working SSH access to the replacement GPU node
- working SSH access to at least one live control-plane node
- the repository-local Python virtualenv available at `.venv/`
- the replacement node already added to `local/hosts.yml`

Assumptions from this incident:

- the control-plane API certificate already contains hostnames such as `cp-1`, `cp-2`, `cp-3`
- the replacement node cannot reach the control-plane private addresses directly
- the replacement node can reach the control-plane public IPs on `6443/tcp`

## Repository Files Updated First

These files were changed before live node onboarding:

- [`local/hosts.yml`](../../local/hosts.yml)
- [`inventory/group_vars/all.yml`](../../inventory/group_vars/all.yml)
- [`bootstrap/playbooks/host-prep.yml`](../../bootstrap/playbooks/host-prep.yml)
- [`bootstrap/playbooks/gpu-prep.yml`](../../bootstrap/playbooks/gpu-prep.yml)
- [`tests/validate-cluster.sh`](../../tests/validate-cluster.sh)
- [`gitops/apps/llm-serving/inference-service.yaml`](../../gitops/apps/llm-serving/inference-service.yaml)
- [`gitops/apps/llm-serving/inference-service-gpt-oss-20b.yaml`](../../gitops/apps/llm-serving/inference-service-gpt-oss-20b.yaml)

Important inventory lessons:

- the new node must be placed into `kube_node` and `gpu`
- control-plane nodes must have explicit `access_ip` when workers join over public IPs
- public `access_ip` values fix worker join and worker-side `nginx-proxy`, but they do not change the node `InternalIP` selected by kubelet
- host-specific SSH users must not be overridden by a global `ansible_user: root`
- the cluster DNS domain must be explicit in inventory and reused by GitOps manifests that build service FQDNs; assuming `cluster.local` will break Grafana and other in-cluster clients on clusters whose DNS domain follows `cluster_name`
- if the replacement GPU node cannot route to other nodes' private `InternalIP` addresses, `Cilium` host and endpoint health will remain degraded even after a successful join
- in that environment, serving and GPU observability need explicit GitOps-managed public endpoints until a private L3 path exists

## Step 1. Verify Repository And Cluster Access

Why:

- to confirm the repo is writable and `origin` is reachable
- to confirm there is at least one control-plane node with working `kubectl`

Commands:

```bash
git remote -v
git ls-remote --heads origin
sshpass -p '<cp-1-root-password>' ssh -o StrictHostKeyChecking=no root@<cp-1-public-ip> 'kubectl get nodes -o wide'
```

Observed problem:

- local kubeconfig at `local/runtime/admin.conf` pointed to `https://127.0.0.1:6443` and was not directly usable from the operator machine

Resolution:

- use SSH to `cp-1` for cluster-side inspection until a better local access path is created

## Step 2. Verify The New GPU Host Before Touching Kubernetes

Why:

- to avoid spending time debugging Kubernetes when the host itself is inaccessible or missing GPUs

Commands:

```bash
ssh -i local/id_ed25519 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  gputester@89.108.125.7 \
  'sudo bash -lc "hostname; whoami; nvidia-smi -L"'
```

Expected result:

- hostname visible
- `sudo` works
- all GPUs visible through `nvidia-smi`

Observed result in this incident:

- hostname was `sxmgpu`
- `sudo` worked
- `8x NVIDIA H200` were visible

## Step 3. Render Inventory With The Replacement Node

Why:

- Kubespray and validation scripts must see the new topology before any host or cluster action

Commands:

```bash
./bootstrap/render-inventory.sh local/hosts.yml inventory/generated/hosts.yml
./tests/validate-cluster.sh hosts
```

Important inventory decisions used here:

- remove `gpu-1` and `gpu-2` from `local/hosts.yml`
- add `sxmgpu`
- set:
  - `ansible_user: gputester`
  - `ansible_ssh_private_key_file: /root/codex/k8s-cloud/local/id_ed25519`
  - `ansible_become: true`
  - `ansible_become_method: sudo`
- add `access_ip` for `cp-1`, `cp-2`, `cp-3` using their public IPs

## Step 4. Use The Repository Virtualenv For Ansible

Why:

- the system `ansible` on the operator machine was broken for this repo and remote execution

Commands:

```bash
ansible --version
.venv/bin/ansible --version
source .venv/bin/activate
```

Observed problem:

- system Ansible `2.10.8` failed with missing `ansible.module_utils.six.moves`

Resolution:

- use only `.venv/bin/ansible` and `.venv/bin/ansible-playbook`

## Step 5. Run Host Preparation On The New Node

Why:

- Kubespray expects base OS dependencies, container runtime prerequisites, and package state to be normalized before join

Commands:

```bash
source .venv/bin/activate
ansible -i inventory/generated/hosts.yml sxmgpu -m ping
ansible -i inventory/generated/hosts.yml sxmgpu -b -m command -a whoami
ansible-playbook -i inventory/generated/hosts.yml bootstrap/playbooks/host-prep.yml --limit sxmgpu -v
```

Observed problem:

- `bootstrap/playbooks/host-prep.yml` and `bootstrap/playbooks/gpu-prep.yml` had `become: false`

Resolution:

- change both playbooks to `become: true`

## Step 6. First Kubespray Join Attempt

Why:

- to let Kubespray perform the normal worker scale-out flow

Commands:

```bash
source /root/codex/k8s-cloud/.venv/bin/activate
cd bootstrap/cache/kubespray
ansible-playbook \
  -i /root/codex/k8s-cloud/inventory/generated/hosts.yml \
  scale.yml \
  --limit=sxmgpu \
  -b -v \
  -e @/root/codex/k8s-cloud/inventory/group_vars/all.yml \
  -e '{"kube_network_plugin":"cilium","kube_proxy_mode":"iptables","container_manager":"containerd","kubeconfig_localhost":true,"download_run_once":false}'
```

Observed problem:

- join failed during `kubeadm join`
- the replacement node could not reach `https://192.168.0.28:6443`

Error shape:

```text
failed to request the cluster-info ConfigMap
Get "https://192.168.0.28:6443/...": Client.Timeout exceeded
```

Why it happened:

- the node could reach control-plane public IPs
- the node could not reach control-plane private IPs
- existing `cluster-info`, `kubeadm-config`, and worker-side `nginx-proxy` still referenced private `192.168.0.x` addresses

## Step 7. Verify Public And Private API Reachability

Why:

- to prove whether the failure is network reachability or kubeadm configuration

Commands run on `sxmgpu`:

```bash
curl -k --connect-timeout 5 https://cp-1:6443/healthz
curl -k --connect-timeout 5 https://192.168.0.28:6443/healthz
nc -vz -w 5 168.222.193.49 6443
nc -vz -w 5 83.166.244.243 6443
nc -vz -w 5 89.111.168.186 6443
```

Observed result:

- public control-plane IPs were reachable
- private control-plane IPs were not

Additional lesson:

- this same reachability pattern later caused broken `Cilium` host and endpoint health between `sxmgpu` and the rest of the cluster, even though `kubeadm join` had already succeeded

## Step 8. Rewrite Kubeadm Discovery To A SAN-Compatible Hostname

Why:

- API certificates already covered `cp-1`, `cp-2`, `cp-3`

## Step 8a. Verify Cross-Node Cilium Health Before Declaring The Node Usable

Why:

- a node can be `Ready` and still be unusable for cross-node pod traffic
- `LiteLLM`, `Open WebUI`, and `vmagent` all depend on successful east-west traffic to the GPU worker

Commands:

```bash
sshpass -p '<cp-1-root-password>' ssh -o StrictHostKeyChecking=no root@<cp-1-public-ip> \
  'kubectl -n kube-system exec ds/cilium -- cilium-dbg node list'

sshpass -p '<cp-1-root-password>' ssh -o StrictHostKeyChecking=no root@<cp-1-public-ip> \
  'kubectl -n kube-system exec cilium-<gpu-cilium-pod> -- cilium status --verbose'
```

Failure signature from this incident:

```text
Cluster health: 1/5 reachable
Host connectivity to 192.168.0.x: context deadline exceeded
Endpoint connectivity to 10.233.x.x: context deadline exceeded
```

Meaning:

- `sxmgpu` could reach public node IPs
- `sxmgpu` could not reach the private `InternalIP` addresses used by Kubernetes and `Cilium`
- cross-node pod traffic from `infra-1` to GPU workloads and GPU telemetry was unreliable or broken

Resolution used in the live cluster:

- keep the cluster joined as-is
- route predictor access through GitOps-managed public `NodePort` services on `sxmgpu`
- route `dcgm-exporter` scraping through a GitOps-managed public `VMStaticScrape`
- document the lack of private L3 reachability as an environment limitation instead of treating the cluster as fully healthy

Preventive rule for future clusters:

- if you want normal in-cluster east-west traffic to work without these fallbacks, ensure every node can route to every other node's Kubernetes `InternalIP` before onboarding the replacement GPU worker

## Step 8b. Prevent Empty Responses From Reasoning-Capable Models

Why:

- both `gpt-oss-20b` and `qwen35-9b` can return reasoning or thinking output instead of a normal short assistant answer
- this breaks the expected UX in `Open WebUI`

Validated fixes used in the live cluster:

- `gpt-oss-20b` through `LiteLLM`:
  - `include_reasoning: false`
  - `reasoning_effort: low`
  - `allowed_openai_params: [reasoning_effort]`
- `qwen35-9b` through `LiteLLM`:
  - `chat_template_kwargs.enable_thinking: false`

Repository source of truth:

- [`gitops/apps/litellm/configmap.yaml`](../../gitops/apps/litellm/configmap.yaml)
- using a public IP directly would have created a TLS SAN mismatch

Commands run from `cp-1`:

```bash
kubectl -n kube-public get configmap cluster-info -o jsonpath='{.data.kubeconfig}' | grep server
kubectl -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | grep controlPlaneEndpoint
```

Desired state:

- `cluster-info` should use `https://cp-1:6443`
- `kubeadm-config` should use `controlPlaneEndpoint: cp-1:6443`

Additional commands run on `sxmgpu`:

```bash
sudo bash -lc 'cat >> /etc/hosts <<EOF
168.222.193.49 cp-1
83.166.244.243 cp-2
89.111.168.186 cp-3
EOF'
```

`kubeadm-client.conf` was updated to use:

```yaml
apiServerEndpoint: "cp-1:6443"
token: <fresh-kubeadm-token>
```

Then a fresh token was created on `cp-1`:

```bash
kubeadm token create --ttl 24h
```

Why a fresh token was created:

- to guarantee a matching JWS entry existed in `kube-public/cluster-info`

## Step 9. Complete The Join

Command used on `sxmgpu`:

```bash
sudo /usr/local/bin/kubeadm join \
  --config /etc/kubernetes/kubeadm-client.conf \
  --ignore-preflight-errors=DirAvailable--etc-kubernetes-manifests \
  --v=3
```

Observed result:

- `sxmgpu` registered in the cluster
- `kubectl get nodes -o wide` showed the new node

But it was still `NotReady`.

## Step 10. Fix Worker-Side `nginx-proxy`

Why:

- Cilium on the worker talks to `https://localhost:6443`
- on non-control-plane nodes this means the local static-pod `nginx-proxy`
- `nginx-proxy` had been rendered with private control-plane IPs

Inspection on `sxmgpu`:

```bash
sudo cat /etc/nginx/nginx.conf
ss -ltnp | grep 6443
```

Observed problem:

```nginx
server 192.168.0.28:6443;
server 192.168.0.4:6443;
server 192.168.0.68:6443;
```

Live fix:

```bash
sudo sed -i \
  -e 's/server 192.168.0.28:6443;/server 168.222.193.49:6443;/' \
  -e 's/server 192.168.0.4:6443;/server 83.166.244.243:6443;/' \
  -e 's/server 192.168.0.68:6443;/server 89.111.168.186:6443;/' \
  /etc/nginx/nginx.conf

sudo crictl ps --name nginx-proxy -q | xargs -r sudo crictl stop
```

Repository fix:

- add `access_ip` for all control-plane nodes in `local/hosts.yml`

Why this repo fix matters:

- Kubespray renders worker `nginx-proxy` upstreams from `main_access_ip`
- without explicit `access_ip`, workers will be pointed back at private control-plane addresses

## Step 11. Fix Cilium Init Failure On `/opt/cni/bin`

Why:

- after the node joined, `cilium` init containers failed

Observed error:

```text
cp: cannot create regular file '/hostbin/cilium-mount': Permission denied
```

Inspection:

```bash
sudo stat -c '%a %U:%G %n' /opt/cni /opt/cni/bin
sudo ls -ld /opt/cni /opt/cni/bin
```

Observed problem:

- `/opt/cni/bin` ownership had drifted to `kube:root`

Fix:

```bash
sudo chown root:root /opt/cni /opt/cni/bin
sudo chmod 755 /opt/cni /opt/cni/bin
```

Then recycle the `cilium` pod on `sxmgpu`:

```bash
kubectl -n kube-system delete pod <cilium-pod-on-sxmgpu> --wait=false
```

Result:

- `sxmgpu` became `Ready`

## Step 12. Apply GPU Role Labels And Taints

Why:

- the node had joined, but it still had no `gpu` role labels
- `nvidia-device-plugin` DaemonSet selected only `node-role.kubernetes.io/gpu=`

Commands:

```bash
kubectl label node sxmgpu node-role.kubernetes.io/gpu='' accelerator=nvidia-h200 --overwrite
kubectl taint node sxmgpu nvidia.com/gpu=true:NoSchedule --overwrite
```

Result:

- `sxmgpu` became a proper GPU scheduling target

## Step 13. Run GPU Preparation

Why:

- install driver and NVIDIA container toolkit on the replacement host

Command:

```bash
source .venv/bin/activate
ansible-playbook -i inventory/generated/hosts.yml bootstrap/playbooks/gpu-prep.yml --limit sxmgpu -v
```

Observed problem:

- after package installation, `nvidia-smi` failed with:

```text
Failed to initialize NVML: Driver/library version mismatch
```

Why:

- user-space packages updated before the running kernel modules matched them

Fix:

```bash
sudo reboot
```

Important lesson:

- after GPU driver installation on a fresh replacement node, validate `nvidia-smi`
- if you see `Driver/library version mismatch`, reboot before debugging Kubernetes

## Step 14. Recover From Reboot Side Effects

After reboot two new issues appeared.

### 14.1 Cilium returned unhealthy

What happened:

- `cilium` came back in a partially healthy state
- `cilium.sock` was not consistently available

### 14.2 `cilium-operator` was stranded on dead nodes

Inspection:

```bash
kubectl -n kube-system get deploy,po -l io.cilium/app=operator -o wide
kubectl get ciliumnode sxmgpu -o yaml
```

Observed problem:

- both `cilium-operator` pods were still on `gpu-1` and `gpu-2`
- `CiliumNode sxmgpu` existed but had empty `spec.ipam`

Why this mattered:

- without a healthy operator on live nodes, `sxmgpu` did not receive a proper Cilium IPAM allocation

Fix:

```bash
kubectl -n kube-system rollout restart deploy/cilium-operator
```

Then verify that new operator pods land on live nodes.

## Step 15. Delete The Stale `CiliumNode` For `sxmgpu`

Why:

- after the operator was moved, the existing `CiliumNode` for `sxmgpu` still lacked `ipam.podCIDRs`

Compare:

```bash
kubectl get ciliumnode cp-1 -o yaml
kubectl get ciliumnode infra-1 -o yaml
kubectl get ciliumnode sxmgpu -o yaml
```

Observed problem:

- working nodes had:

```yaml
spec:
  ipam:
    podCIDRs:
    - <cidr>
```

- `sxmgpu` did not

Fix:

```bash
kubectl delete ciliumnode sxmgpu
kubectl -n kube-system delete pod <cilium-pod-on-sxmgpu> --wait=false
```

Result after operator recovery:

- new `CiliumNode sxmgpu` was recreated
- `spec.ipam.podCIDRs` appeared
- `/var/run/cilium/cilium.sock` appeared

Validation on the host:

```bash
sudo ls -la /var/run/cilium
sudo curl --unix-socket /var/run/cilium/cilium.sock http://localhost/v1/config
```

## Step 16. Fix NVIDIA Runtime For `containerd`

Why:

- `nvidia-device-plugin` still failed after the host itself could see GPUs

Observed error from pod logs:

```text
Failed to initialize NVML: ERROR_LIBRARY_NOT_FOUND
```

Why it happened:

- the host driver was fine
- container runtime configuration still launched ordinary pods with the default `runc` runtime
- the NVIDIA runtime was present but not actually defaulted for CRI

Diagnostics on `sxmgpu`:

```bash
sudo nvidia-smi -L
sudo grep -n "nvidia" /etc/containerd/config.toml /etc/containerd/conf.d/*.toml
sudo nvidia-ctk --version
```

Runtime fix:

```bash
sudo nvidia-ctk runtime configure \
  --runtime=containerd \
  --config=/etc/containerd/config.toml \
  --set-as-default=false
```

Then inspect the generated drop-in:

```bash
sudo cat /etc/containerd/conf.d/99-nvidia.toml
```

Observed problem:

- generated config still had:

```toml
default_runtime_name = "runc"
```

Final fix:

```bash
sudo sed -i \
  's/default_runtime_name = "runc"/default_runtime_name = "nvidia"/' \
  /etc/containerd/conf.d/99-nvidia.toml

sudo systemctl restart containerd kubelet
```

Then recycle the device plugin pod:

```bash
kubectl -n kube-system delete pod <nvidia-device-plugin-pod-on-sxmgpu> --wait=false
```

Result:

- `nvidia-device-plugin` started successfully on `sxmgpu`
- Kubernetes exposed `nvidia.com/gpu=8`

Validation:

```bash
kubectl get node sxmgpu -o jsonpath='{.status.allocatable.nvidia\.com/gpu} {.status.capacity.nvidia\.com/gpu}'
```

Expected result:

```text
8 8
```

## Step 17. Remove Dead GPU Nodes From The Cluster

Only do this after the replacement node is:

- `Ready`
- labeled as `gpu`
- exposing `nvidia.com/gpu`

Command:

```bash
kubectl delete node gpu-1 gpu-2
```

Validation:

```bash
kubectl get nodes -o wide
```

Expected result:

- only live nodes remain in the API

## Step 18. Post-Replacement Serving Check

Even after the cluster-side node replacement succeeds, application workloads may still be pinned to old hostnames.

In this incident:

- `gpt-oss-20b` was still selecting `kubernetes.io/hostname=gpu-1`
- `qwen35-9b` was still selecting `kubernetes.io/hostname=gpu-2`

Check:

```bash
kubectl -n llm get pods -o wide
kubectl -n llm describe pod <pending-pod>
```

If the events show old hostname selectors, reconcile the manifests that pin GPU workloads.

## Condensed Procedure For Future GPU Node Additions

1. Update `local/hosts.yml`
   - add the new GPU node
   - ensure control-plane nodes have public `access_ip`
2. Render inventory and validate host contract
3. Use `.venv` Ansible only
4. Run `bootstrap/playbooks/host-prep.yml` on the new node
5. Run Kubespray `scale.yml`
6. If join fails on `192.168.0.x:6443`
   - switch discovery to `cp-1:6443`
   - map `cp-1`, `cp-2`, `cp-3` in `/etc/hosts`
   - ensure `cluster-info` and `kubeadm-config` no longer point at private IPs for this join path
7. Fix worker `nginx-proxy` if it still proxies to private control-plane IPs
8. If Cilium init fails on `/opt/cni/bin`
   - force `/opt/cni/bin` to `root:root`
9. Label and taint the node for GPU scheduling
10. Run `gpu-prep`
11. If `nvidia-smi` shows driver/library mismatch
   - reboot
12. After reboot
   - verify `cilium-operator` is not stranded on removed nodes
   - restart `cilium-operator` if needed
   - recreate stale `CiliumNode` if IPAM is empty
13. Configure NVIDIA runtime in `containerd`
   - ensure runtime exists
   - ensure `default_runtime_name = "nvidia"`
   - restart `containerd` and `kubelet`
14. Wait for `nvidia-device-plugin` to become healthy
15. Verify `nvidia.com/gpu`
16. Only then delete old GPU node objects
17. Reconcile workload nodeSelectors if they still point to retired hostnames

## Failure Signatures And Their Fixes

`kubeadm join` times out on `192.168.0.x:6443`

- Cause: worker cannot reach private control-plane IPs
- Fix: use public `access_ip`, hostname-based SAN-compatible API endpoint, and public-IP worker `nginx-proxy`

`cilium` init fails with `cp: cannot create regular file '/hostbin/cilium-mount': Permission denied`

- Cause: `/opt/cni/bin` ownership drifted away from `root:root`
- Fix: `chown root:root /opt/cni /opt/cni/bin`

`nvidia-smi` reports `Driver/library version mismatch`

- Cause: new user-space packages, old loaded kernel module
- Fix: reboot

`CiliumNode` exists but has empty `spec.ipam`

- Cause: `cilium-operator` unavailable or stranded on removed nodes
- Fix: relocate/restart `cilium-operator`, then recreate `CiliumNode` and `cilium` pod on the new worker

`nvidia-device-plugin` fails with `ERROR_LIBRARY_NOT_FOUND`

- Cause: `containerd` is not using NVIDIA runtime for CRI
- Fix: configure NVIDIA runtime and ensure `default_runtime_name = "nvidia"`, then restart `containerd` and `kubelet`

`vLLM` fails with `cudaGetDeviceCount() ... Error 802: system not yet initialized` on NVSwitch hosts

- Cause: NVSwitch fabric is not activated yet even though `nvidia-smi -L` and `nvidia.com/gpu` already look healthy
- Fix: install and start `nvidia-fabricmanager`, then verify `nvidia-smi -q` reports `Fabric -> State: Completed` and `Status: Success`; if fabric is still `In Progress`, complete a reboot/revalidation cycle

`vLLM` fails with `Cannot find any model weights with /mnt/models`

- Cause: KServe downloaded an incomplete S3 prefix where only Hugging Face `.metadata` side files existed and the actual `model.safetensors-*` shards were still missing
- Fix: wait for shard upload to finish, confirm the real shard objects exist in S3, then recycle the affected predictor pod so it downloads the completed prefix

## Final Validation Checklist

Run:

```bash
kubectl get nodes -o wide
kubectl get node sxmgpu -o jsonpath='{.status.allocatable.nvidia\.com/gpu} {.status.capacity.nvidia\.com/gpu}'
kubectl -n kube-system get pods -o wide | egrep 'cilium|nvidia-device-plugin|cilium-operator'
kubectl -n llm get pods -o wide
```

Success means:

- replacement node is `Ready`
- `nvidia.com/gpu` is present and correct
- `cilium` and `cilium-operator` are healthy on live nodes
- dead GPU nodes are gone from the API
- application workloads no longer depend on retired node names
