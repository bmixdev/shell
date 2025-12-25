#Bash-скрипт: создать много VM (Pod+Service+Ingress) + env + mount

#Скрипт генерит YAML “на лету” и применяет.
#Создай файл vm_create.sh:

#!/usr/bin/env bash
set -euo pipefail

# ===== НАСТРОЙКИ ПО УМОЛЧАНИЮ =====
NAMESPACE="${NAMESPACE:-default}"
HOST="${HOST:-server.example.com}"
INGRESS_CLASS="${INGRESS_CLASS:-nginx}"

IMAGE_DEFAULT="${IMAGE_DEFAULT:-nexus.mycorp.local:5000/myteam/myimage:tag}"
PORT_DEFAULT="${PORT_DEFAULT:-8081}"

# Пример "путей": монтируем /data как emptyDir (временный)
# Если хочешь PVC - см. ниже в комментарии.
MOUNT_DATA="${MOUNT_DATA:-/data}"

# ===== ИСПОЛЬЗОВАНИЕ =====
# ./vm_create.sh vm-001 [image] [port]
NAME="${1:-}"
IMAGE="${2:-$IMAGE_DEFAULT}"
PORT="${3:-$PORT_DEFAULT}"

if [[ -z "$NAME" ]]; then
  echo "Usage: $0 <vm-name> [image] [port]"
  echo "Example: $0 vm-001 nexus.../img:tag 8081"
  exit 1
fi

# простая валидация имени (dns-safe)
if ! [[ "$NAME" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
  echo "ERROR: name must be dns-safe: a-z0-9 and '-'"
  exit 2
fi

# ===== НАСТРАИВАЕМЫЕ ENV ПЕРЕМЕННЫЕ ДЛЯ VM =====
# Хочешь добавлять свои - дописывай блок env: ниже.
JAVA_OPTS="${JAVA_OPTS:-"-Xms256m -Xmx512m"}"
DBI_CONTEXT="${DBI_CONTEXT:-"/dbi"}"
MY_PARAM="${MY_PARAM:-"value1"}"

cat <<EOF | kubectl -n "$NAMESPACE" apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${NAME}-config
data:
  app.properties: |
    # пример файла конфигурации
    key1=value1
    key2=value2
---
apiVersion: v1
kind: Pod
metadata:
  name: ${NAME}
  labels:
    app: ${NAME}
spec:
  containers:
    - name: vm
      image: ${IMAGE}
      imagePullPolicy: IfNotPresent
      ports:
        - containerPort: ${PORT}

      # ===== ENV переменные внутрь контейнера =====
      env:
        - name: JAVA_OPTS
          value: "${JAVA_OPTS}"
        - name: DBI_CONTEXT
          value: "${DBI_CONTEXT}"
        - name: MY_PARAM
          value: "${MY_PARAM}"

      # ===== Монтирование путей =====
      volumeMounts:
        - name: data
          mountPath: ${MOUNT_DATA}
        - name: conf
          mountPath: /opt/app/conf
          readOnly: true

  volumes:
    # /data как временный том
    - name: data
      emptyDir: {}

    # configmap как файлы в /opt/app/conf
    - name: conf
      configMap:
        name: ${NAME}-config
---
apiVersion: v1
kind: Service
metadata:
  name: ${NAME}
spec:
  selector:
    app: ${NAME}
  ports:
    - name: http
      port: 80
      targetPort: ${PORT}
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${NAME}
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: "/\$2"
spec:
  ingressClassName: ${INGRESS_CLASS}
  rules:
    - host: ${HOST}
      http:
        paths:
          - path: /vm/${NAME}(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: ${NAME}
                port:
                  number: 80
EOF

echo "Created VM: ${NAME}"
echo "URL: https://${HOST}/vm/${NAME}/dbi/"
kubectl -n "$NAMESPACE" get pod "${NAME}" -o wide
kubectl -n "$NAMESPACE" get svc "${NAME}"
kubectl -n "$NAMESPACE" get ing "${NAME}"


#Запуск:

chmod +x vm_create.sh
./vm_create.sh vm-001
./vm_create.sh vm-002 nexus.mycorp.local:5000/myteam/myimage:tag 8081


#Удаление VM:

kubectl delete pod,svc,ing,configmap -n default vm-001 vm-001-config
# (для скрипта будет: configmap vm-001-config это NAME-config)
kubectl delete configmap -n default vm-001-config
