# Talos Kubernetes no Proxmox — homelab

Este repositório cria um cluster Talos Linux no Proxmox e mantém a plataforma Kubernetes por Helm e Argo CD. Este documento registra o estado implantado em 12/07/2026, os acessos, DNS, credenciais, operação e diagnóstico.

> **Segurança:** senhas não são gravadas em texto puro no Git. As seções de acesso mostram como consultá-las nos Secrets do Kubernetes. A senha `root` do Proxmox que já foi compartilhada deve ser trocada; a operação normal usa chave SSH.

## Estado atual

| Item | Valor |
|---|---|
| Proxmox | `192.168.88.249`, nó `proxmox1` |
| Cluster | `my-talos` |
| Talos | `v1.13.3` |
| Kubernetes | `v1.36.2` |
| API Kubernetes (VIP) | `192.168.88.85:6443` |
| VMs | IDs `901`, `902` e `903` |
| IPs dos nós | `192.168.88.116`, `.117` e `.118` |
| Recursos por VM | 4 vCPU, 16 GiB RAM e disco de 100 GiB |
| Storage Proxmox | `local-lvm` |
| StorageClass Kubernetes | `local-path` (padrão) |
| IP do Istio Ingress | `192.168.88.160` |
| Pool MetalLB | `192.168.88.160-192.168.88.200` |
| Repositório GitOps | `https://github.com/vitorbiazotti/proxmox-talos-main` |

Os três nós são control planes e aceitam workloads. O CNI é instalado como parte da preparação do cluster. Istio é o gateway HTTP/HTTPS dos serviços web.

## Pré-requisitos no Mac

- Acesso SSH por chave ao Proxmox.
- `kubectl`, `helm`, `helmfile`, `git`, `ruby` e, para o menu, `dialog`.
- Acesso à rede `192.168.88.0/24`.

Instalação das ferramentas com Homebrew:

```bash
brew install kubectl helm helmfile ruby dialog
```

### Configurar SSH do Proxmox

O erro `ssh-copy-id: No identities found` significa que ainda não havia uma chave local. Crie e instale uma:

```bash
ssh-keygen -t ed25519 -C "proxmox-homelab"
ssh-copy-id root@192.168.88.249
ssh root@192.168.88.249
```

Depois disso, os scripts não devem pedir a senha do Proxmox.

## Scripts do cluster

Execute a partir da raiz do repositório:

```bash
chmod +x menu.sh redeploy.sh talos-proxmox-manager.sh
./menu.sh
```

O [menu.sh](menu.sh) envia o [talos-proxmox-manager.sh](talos-proxmox-manager.sh) por SSH para o Proxmox e oferece:

1. criar o cluster;
2. iniciar as VMs;
3. parar as VMs;
4. excluir o cluster;
5. recriar tudo;
6. sair.

Também é possível executar diretamente:

```bash
cat talos-proxmox-manager.sh | ssh root@192.168.88.249 'bash -s -- --create'
cat talos-proxmox-manager.sh | ssh root@192.168.88.249 'bash -s -- --start'
cat talos-proxmox-manager.sh | ssh root@192.168.88.249 'bash -s -- --stop'
cat talos-proxmox-manager.sh | ssh root@192.168.88.249 'bash -s -- --delete'
```

O `redeploy.sh` apaga as VMs, configura o cluster novamente e executa o Helmfile. **Ele é destrutivo e remove todos os dados armazenados nos volumes locais.** Faça backup antes de usá-lo.

As variáveis principais ficam no início de `talos-proxmox-manager.sh`. Antes de recriar, confirme especialmente `PROXMOX_NODE`, `DISK_STORAGE`, `VIP_IP`, `TALOS_VERSION`, `K8S_VERSION`, RAM, CPU e tamanho do disco.

## Kubeconfig e comandos básicos

O kubeconfig funcional no Mac é:

```bash
export KUBECONFIG="$HOME/.kube/talos-kubeconfig"
kubectl get nodes -o wide
kubectl get pods -A
```

No Proxmox, os arquivos Talos ficam em `/root/myTalosCluster`. Para recuperar o kubeconfig novamente:

```bash
mkdir -p ~/.kube
scp root@192.168.88.249:/root/.kube/config ~/.kube/talos-kubeconfig
chmod 600 ~/.kube/talos-kubeconfig
```

## GitOps e Helm

O [helmfile.yaml](helmfile.yaml) é o controle central dos charts, versões e valores. O gerador cria Applications do Argo CD em `gitops/applications/platform-addons.yaml`.

Fluxo normal para alterar um addon:

```bash
export KUBECONFIG="$HOME/.kube/talos-kubeconfig"

# editar helmfile.yaml
ruby gitops/generate-applications.rb
git diff
git add helmfile.yaml gitops/applications/platform-addons.yaml
git commit -m "Atualiza addons da plataforma"
git push origin main
```

O Argo CD reconcilia o repositório automaticamente. Para verificar:

```bash
kubectl -n argocd get applications
kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
```

O `helmfile sync` deve ser reservado à implantação inicial ou recuperação. No uso cotidiano, prefira alterações via GitOps.

## Addons instalados

| Addon | Namespace | Função/interface |
|---|---|---|
| MetalLB | `metallb-system` | IPs LoadBalancer |
| Istio | `istio-system`, `istio-ingress` | service mesh e gateway web |
| cert-manager | `cert-manager` | certificados internos |
| metrics-server | `kube-system` | métricas para `kubectl top` e HPA |
| Kyverno | `kyverno` | políticas Kubernetes |
| Policy Reporter | `policy-reporter` | interface dos relatórios Kyverno |
| Argo CD | `argocd` | GitOps, sem login neste homelab |
| Argo Rollouts | `argo-rollouts` | progressive delivery e dashboard |
| Argo CD Image Updater | `argocd` | atualização de imagens |
| Argo Events | `argo-events` | eventos e sensores |
| Argo Workflows | `argo-workflows` | workflows, modo `server` local |
| Loki | `monitoring` | logs consultados pelo Grafana |
| kube-prometheus-stack | `monitoring` | Prometheus, Alertmanager e Grafana |
| OpenTelemetry Collector | `observability` | coleta de telemetria |
| KEDA | `keda` | autoscaling baseado em eventos |
| VPA | `vpa` | recomendações/ajuste vertical |
| HPA | API nativa | autoscaling horizontal |
| External Secrets | `external-secrets` | sincronização de secrets externos |
| Goldilocks | `goldilocks` | recomendações de CPU e memória |
| Jenkins | `jenkins` | CI/CD |
| Zabbix | `zabbix` | servidor, frontend e PostgreSQL |
| Zabbix Kubernetes | `zabbix-monitoring` | proxy, agentes e kube-state-metrics |
| local-path-provisioner | `local-path-provisioner` | volumes persistentes locais |

As versões exatas dos charts estão fixadas em `helmfile.yaml`.

## DNS no UCG Fiber e AdGuard Home

O UCG Fiber distribui o AdGuard Home como DNS da rede. Os servidores usados são `192.168.88.110` e `192.168.88.247`; o gateway UCG é `192.168.88.1`.

No AdGuard Home, abra **Filters → DNS rewrites** e crie os registros abaixo, todos apontando para `192.168.88.160`:

```text
argocd.home.arpa
grafana.home.arpa
prometheus.home.arpa
alertmanager.home.arpa
workflows.home.arpa
rollouts.home.arpa
goldilocks.home.arpa
kyverno.home.arpa
jenkins.home.arpa
zabbix.home.arpa
```

Teste no Mac:

```bash
dig +short workflows.home.arpa
dig +short zabbix.home.arpa
```

Ambos devem retornar `192.168.88.160`. Se o resultado estiver antigo:

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

## Certificado HTTPS interno

As interfaces usam certificados emitidos pela CA interna `homelab-ca`. A CA exportada está em `~/.kube/homelab-root-ca.crt`. Para confiar nela no macOS:

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  ~/.kube/homelab-root-ca.crt
```

## Links e credenciais

| Sistema | Link | Autenticação |
|---|---|---|
| Argo CD | https://argocd.home.arpa | desabilitada |
| Grafana | https://grafana.home.arpa | usuário `admin`; senha no Secret |
| Prometheus | https://prometheus.home.arpa | sem login |
| Alertmanager | https://alertmanager.home.arpa | sem login |
| Argo Workflows | https://workflows.home.arpa | modo local/server, sem token |
| Argo Rollouts | https://rollouts.home.arpa | sem login |
| Goldilocks | https://goldilocks.home.arpa | sem login |
| Kyverno/Policy Reporter | https://kyverno.home.arpa | sem login |
| Jenkins | https://jenkins.home.arpa | usuário e senha no Secret |
| Zabbix | https://zabbix.home.arpa | usuário e senha no Secret |

Consultar a senha do Grafana:

```bash
kubectl -n monitoring get secret kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Consultar usuário e senha do Jenkins:

```bash
kubectl -n jenkins get secret jenkins \
  -o jsonpath='{.data.jenkins-admin-user}' | base64 -d; echo
kubectl -n jenkins get secret jenkins \
  -o jsonpath='{.data.jenkins-admin-password}' | base64 -d; echo
```

Consultar usuário e senha atuais do Zabbix:

```bash
kubectl -n zabbix get secret zabbix-admin-credentials \
  -o jsonpath='{.data.username}' | base64 -d; echo
kubectl -n zabbix get secret zabbix-admin-credentials \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

O Secret `zabbix-admin-credentials` é um registro operacional criado no cluster e não é versionado. Se o banco do Zabbix for recriado, redefina a senha e atualize esse Secret.

> Argo CD e Argo Workflows estão sem autenticação porque o ambiente é uma LAN privada. Não exponha esses endereços à Internet. Para acesso remoto, use VPN e reative autenticação/SSO.

## Zabbix: onde aparecem pods e addons

A integração está ativa. O proxy `zabbix-kubernetes-proxy`, os três agentes e o `kube-state-metrics` estão em execução. O Zabbix descobriu recursos dos namespaces Argo, cert-manager, Goldilocks, Istio, Jenkins, monitoring, Kyverno e outros.

Os pods **não aparecem como hosts independentes** na tela de Hosts. Eles são itens descobertos nos hosts lógicos criados pelo template oficial:

1. abra **Monitoring → Latest data**;
2. em **Hosts**, selecione `Kubernetes nodes` para pods, containers, nós e uso de recursos;
3. selecione `Kubernetes cluster state` para deployments, namespaces, daemonsets e estado do cluster;
4. limpe filtros/tags antigos, clique **Apply** e pesquise pelo nome, por exemplo `argo`, `jenkins` ou `istio`;
5. use `Kubernetes API server` para métricas da API.

Validação pelo Kubernetes:

```bash
kubectl -n zabbix-monitoring get pods
kubectl -n zabbix-monitoring logs deploy/zabbix-kubernetes-zabbix-helm-chart-proxy --tail=100
```

Se o proxy estiver conectado, o log contém recebimento de configuração do servidor. A descoberta inicial pode levar alguns minutos após uma reinstalação.

## Argo Workflows sem tela de login

O servidor está configurado com `--auth-mode=server`, usando a ServiceAccount do próprio servidor. O gateway também redireciona `/login` para `/` e impede cache da interface.

Abra diretamente:

```text
https://workflows.home.arpa/
```

Se ainda aparecer a página pedindo token, ela está no armazenamento local do navegador:

1. abra as ferramentas do navegador;
2. apague os dados do site `workflows.home.arpa` (cookies, local storage e cache);
3. feche todas as abas desse endereço;
4. abra novamente ou teste em uma janela anônima.

Confirme o modo implantado:

```bash
kubectl -n argo-workflows get deploy argo-workflows-server \
  -o jsonpath='{.spec.template.spec.containers[0].args}'; echo
curl -k https://workflows.home.arpa/api/v1/userinfo
```

O argumento deve conter `--auth-mode=server`, e `/api/v1/userinfo` deve responder sem token.

## Goldilocks

Goldilocks só mostra recomendações para namespaces rotulados. Os namespaces principais já foram habilitados. Para adicionar outro:

```bash
kubectl label namespace NAMESPACE \
  goldilocks.fairwinds.com/enabled=true --overwrite
```

Verifique os VPAs gerados:

```bash
kubectl get vpa -A
```

## Logs, métricas e interfaces

- Loki não tem UI própria neste projeto. No Grafana, use **Explore → Loki**.
- Kyverno não possui UI oficial completa; `kyverno.home.arpa` aponta para o Policy Reporter.
- cert-manager, metrics-server, KEDA, VPA, External Secrets, OpenTelemetry, Argo Events e Image Updater são controladores sem interface web própria.
- HPA é uma API nativa do Kubernetes, não um addon com UI.

Comandos úteis:

```bash
kubectl get pods -A
kubectl get svc -A
kubectl get ingress,virtualservice,gateway -A
kubectl top nodes
kubectl top pods -A
kubectl get pvc -A
kubectl get applications -n argocd
```

## Persistência e backup

Os volumes usam `local-path`, portanto os dados ficam no disco do nó onde o pod foi agendado. Há persistência para Prometheus, Grafana, Loki, Jenkins, PostgreSQL/Zabbix e proxy Zabbix. Isso é adequado ao homelab, mas não oferece replicação automática entre nós.

Antes de excluir/recriar VMs, faça backup de:

- repositório Git;
- VMs/discos no Proxmox;
- banco PostgreSQL do Zabbix;
- Jenkins home;
- configurações/dashboards importantes do Grafana;
- `~/.kube/talos-kubeconfig`, CA interna e configuração Talos.

## Diagnóstico rápido

```bash
export KUBECONFIG="$HOME/.kube/talos-kubeconfig"

kubectl get nodes
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
kubectl -n istio-ingress get svc
kubectl -n argocd get applications
kubectl get events -A --sort-by='.lastTimestamp' | tail -50
```

Teste todos os endpoints:

```bash
for host in argocd grafana prometheus alertmanager workflows rollouts goldilocks kyverno jenkins zabbix; do
  printf '%-15s ' "$host"
  curl -k -sS -o /dev/null -w '%{http_code}\n' "https://$host.home.arpa/"
done
```

Respostas `200`, `302` ou `403` podem ser normais conforme a aplicação; falha de DNS ou conexão indica verificar AdGuard, MetalLB e Istio.
