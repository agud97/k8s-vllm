# Role

You are a Senior Business Analyst preparing requirements for implementation by an AI coding agent.

# Task
Analyze the following feature request and identify:
1.AMBIGUITIES - unclear or vague statements that need clarification
2.MISSING INFORMATION - what's not specified but needed for implementation
3.IMPLICIT ASSUMPTIONS - things that seem assumed but should be explicit
4.EDGE CASES - scenarios not addressed in the description
5.CLARIFYING QUESTIONS - questions to ask the stakeholder

**Important** Use the AskUserTool to clarify the questions with the user. Ask the questions sequentially, one question at a time, one by one.


# Feature Request
See @file:proposal.md 

# Output Format
Provide your analysis in structured sections. For each clarifying question, explain WHY this information matters for implementation.

# Output File
Write the results into spec/requirements.md file

Eсть акаунт в публичном облаке.  Я там могу создать GPU-ноды, а также просто виртуалки. Я хочу отработать механизм развертывания kubernetes-кластера(не managed), в котором будет минимум две GPU ноды с картами A5000. В этом кластере я хочу запустить LLM-модель с помощью kserve+vllm. Все что внутри кластера, должно разворачиваться с помощью ArgoCD и GitOps подхода.20:00Архитектура развертывания Kubernetes + LLM (KServe/vLLM) через GitOps
Это серьёзный и многоуровневый проект. Давай разложу его на слои и дам тебе полный план действий.
Общая архитектура
Вот как выглядит целевое состояние:
  ::view-transition-group(*),
  ::view-transition-old(*),
  ::view-transition-new(*) {
    animation-duration: 0.25s;
    animation-timing-function: cubic-bezier(0.19, 1, 0.22, 1);
  }
VvisualizeVvisualize show_widgetТеперь давай пройдёмся по каждому слою с конкретными шагами и рекомендациями. Нажимай на элементы диаграммы для деталей по каждому блоку.

Фаза 1 — Инфраструктура (виртуалки в облаке)
Тебе понадобится минимум 5-6 VM:
Control plane — 3 VM для HA (рекомендую 4 vCPU, 8 GB RAM, SSD). GPU-ноды — 2 VM с A5000 (минимум 16 GB RAM на ноду, лучше 32 GB; CPU 8+ ядер). Infra-нода — 1 VM для ArgoCD, мониторинга, Istio (4-8 vCPU, 16 GB RAM).
На всех нодах — Ubuntu 24.04 LTS, containerd как CRI.
Фаза 2 — Развёртывание Kubernetes
Два основных варианта для bare-metal / VM кластера:
Kubespray (Ansible-based) — проще для начала, декларативный инвентори, поддерживает HA из коробки. kubeadm — больше контроля, но больше ручной работы. Для отработки механизма kubespray удобнее.
Ключевые настройки: CNI — Calico или Cilium; включить RuntimeClass для GPU workloads; настроить containerd с поддержкой NVIDIA runtime.
Фаза 3 — GPU-поддержка
На каждой GPU-ноде нужно:

Установить NVIDIA drivers (535+ для A5000)
Установить NVIDIA Container Toolkit (nvidia-ctk)
Настроить containerd для использования nvidia runtime
Задеплоить NVIDIA Device Plugin как DaemonSet — он экспортирует nvidia.com/gpu ресурс в Kubernetes
Опционально — GPU Feature Discovery для автоматических лейблов нод

После этого поды смогут запрашивать resources.limits: nvidia.com/gpu: 1.
Фаза 4 — ArgoCD + GitOps
ArgoCD ставится первым (bootstrap) — обычно через Helm вручную один раз, а дальше он управляет сам собой через app-of-apps паттерн.
Рекомендуемая структура Git-репозитория:
gitops-repo/
├── infrastructure/
│   ├── argocd/           # ArgoCD self-management
│   ├── nvidia-device-plugin/
│   ├── cert-manager/
│   ├── istio/
│   └── knative-serving/
├── platform/
│   ├── kserve/
│   └── monitoring/       # Prometheus + Grafana
├── applications/
│   └── llm-inference/
│       ├── inference-service.yaml
│       └── kustomization.yaml
└── apps-of-apps.yaml     # Root ArgoCD Application
ArgoCD Application для каждого компонента указывает на свою директорию в этом репо. Root apps-of-apps.yaml — единственная точка входа.
Фаза 5 — KServe + vLLM
Зависимости KServe: cert-manager, Istio (или Kourier), Knative Serving. Всё это деплоится через ArgoCD.
InferenceService для vLLM выглядит примерно так:
yamlapiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: llama3-vllm
spec:
  predictor:
    model:
      modelFormat:
        name: vllm
      runtime: kserve-vllm
      storageUri: "pvc://model-store/llama-3-8b"  # или s3://
      resources:
        limits:
          nvidia.com/gpu: "2"    # 2 GPU = 2 ноды
        requests:
          cpu: "4"
          memory: "24Gi"
      args:
        - "--tensor-parallel-size=2"
        - "--max-model-len=4096"
Для распределения модели на 2 GPU ноды с tensor parallelism, потребуется vLLM с --tensor-parallel-size=2 и правильно настроенный multi-node inference (через Ray или LeaderWorkerSet). Для модели типа Llama 3 8B хватит одной A5000 (24 GB VRAM), но для моделей побольше (70B) нужен будет multi-GPU.
Фаза 6 — Хранилище моделей
Варианты: PersistentVolume (NFS/Ceph) для простоты, S3-compatible storage (MinIO) если хочется совместимость с облачными паттернами. KServe умеет тянуть модели из обоих вариантов через storage initializer.
Порядок действий (roadmap)

Поднять VM, настроить сеть между ними
Развернуть K8s через kubespray
Настроить GPU ноды (драйверы, containerd, device plugin)
Bootstrap ArgoCD (один helm install)
Закоммитить всё остальное в Git → ArgoCD подхватит
cert-manager → Istio → Knative → KServe (в порядке зависимостей, ArgoCD sync waves)
Загрузить модель в storage
Задеплоить InferenceService

Хочешь, чтобы я детально расписал какой-то конкретный этап — например, сгенерировал готовые манифесты для ArgoCD app-of-apps, или Ansible inventory для kubespray, или полный набор yaml для KServe?в облаке также есть s3 хранилище. Но нет сетевого блочного хранилища. Можно использовать openebs как csi для локальных дисков.
Хочу, чтобы запустилась модель qwen3.5.20:04Хорошо, уточню архитектуру под твои условия. Но сначала нужно определиться с размером Qwen 3.5 — от этого зависит вся конфигурация GPU.Searched the webSearched the webОтлично, теперь картина ясна. Qwen 3.5 — это целое семейство моделей, и у тебя 2 × A5000 (по 24 GB VRAM каждая = 48 GB суммарно). Нужно выбрать правильный размер.
Вот что реально помещается на твоё железо:
  ::view-transition-group(*),
  ::view-transition-old(*),
  ::view-transition-new(*) {
    animation-duration: 0.25s;
    animation-timing-function: cubic-bezier(0.19, 1, 0.22, 1);
  }
VvisualizeVvisualize show_widgetДля твоих 2 × A5000 реалистичны три варианта. Qwen3.5-27B (dense) — сильнейший по качеству, в Q4-квантизации занимает ~17 GB VRAM Insiderllm, а в BF16 потребует обе карты через tensor parallelism. Qwen3.5-35B-A3B (MoE) — интересная альтернатива: активирует только 3B параметров на токен Substack, что делает его быстрее на инференсе, при этом качество на уровне 27B. Qwen3.5-9B — если хочется запас VRAM для большого контекста.
Какой вариант тебе интереснее? Это определит всю дальнейшую конфигурацию.А пока ты выбираешь модель, вот обновлённая архитектура с учётом твоих уточнений — S3 для моделей, OpenEBS для локальных дисков, без сетевого блочного хранилища:
Хранилище:

S3 (облачное) — для хранения весов модели. KServe умеет тянуть модели напрямую из S3 через storage initializer, это оптимальный вариант.
OpenEBS (LocalPV / LVM) — как CSI для всего, что требует PersistentVolume: etcd данные, ArgoCD state, Prometheus TSDB, логи. OpenEBS LocalPV привязывает PV к конкретной ноде, что отлично подходит для stateful-нагрузок на выделенных нодах.

Важные нюансы с OpenEBS:

OpenEBS LocalPV не реплицирует данные между нодами — если нода упала, данные недоступны. Для production etcd это решается HA-кластером (3 control plane ноды, каждая со своим LocalPV).
Для мониторинга (Prometheus/Grafana) — LocalPV на infra-ноде вполне достаточно.
OpenEBS деплоится через ArgoCD как часть infrastructure layer.
Q: Какую модель Qwen 3.5 разворачиваем?
A: Qwen3.5-27B (dense) — максимум качества, TP=2 на обе GPUQ: Формат весов?
A: AWQ/GPTQ Q4 (квантизация, экономия VRAM)20:07Отличный выбор. Qwen3.5-27B в Q4 на двух A5000 с tensor parallelism — это ~17 GB на веса + остаётся ~31 GB на KV-cache, что даёт комфортный контекст до 32-64K токенов.

Всю работу по настройке серверов, кубернетс,должен сделать агент.
