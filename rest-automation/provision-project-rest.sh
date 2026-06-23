#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso: provision-project-rest.sh <proyecto> <entorno>

Crea un namespace y aplica recursos del workshop vía API REST (curl).

Argumentos:
  proyecto   Nombre corto de la aplicación (ej. demo-app)
  entorno    Entorno lógico (ej. desarrollo, qa, produccion)

El namespace resultante será: <entorno>-<proyecto>
Ejemplo: provision-project-rest.sh usuario21 qa
         → namespace qa-usuario21

En OpenShift, usuarios sin cluster-admin crean el proyecto vía ProjectRequest
si POST /api/v1/namespaces devuelve 403.

Requisitos: oc login previo, curl.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 2 ]]; then
  usage
  exit "${1:+0}"
fi

PROYECTO="$1"
ENTORNO="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
ROLEBINDINGS_DIR="${TEMPLATES_DIR}/rolebindings"

NAMESPACE="${ENTORNO}-${PROYECTO}"

if ! oc whoami >/dev/null 2>&1; then
  echo "ERROR: ejecuta 'oc login' antes de continuar." >&2
  exit 1
fi

SERVER="$(oc whoami --show-server)"
TOKEN="$(oc whoami -t)"

render_template() {
  local file="$1"
  sed \
    -e "s/__NAMESPACE__/${NAMESPACE}/g" \
    -e "s/__ENTORNO__/${ENTORNO}/g" \
    -e "s/__PROYECTO__/${PROYECTO}/g" \
    "$file"
}

api_call() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local content_type="${4:-application/json}"

  local args=(
    -ks
    -w "\n%{http_code}"
    -X "$method"
    "${SERVER}${path}"
    -H "Authorization: Bearer ${TOKEN}"
  )

  if [[ -n "$body" ]]; then
    args+=(-H "Content-Type: ${content_type}" -d "$body")
  fi

  local response
  response="$(curl "${args[@]}")"
  local http_code="${response##*$'\n'}"
  local payload="${response%$'\n'*}"

  echo "$http_code"
  if [[ -n "$payload" ]]; then
    echo "$payload"
  fi
}

apply_resource() {
  local label="$1"
  local method="$2"
  local path="$3"
  local template="$4"

  local body
  body="$(render_template "$template")"

  echo "→ ${label}"
  local output http_code payload
  output="$(api_call "$method" "$path" "$body")"
  http_code="${output%%$'\n'*}"
  payload="${output#*$'\n'}"

  case "$http_code" in
    200|201)
      echo "  OK (${http_code})"
      ;;
    409)
      echo "  Ya existe (${http_code}), se continúa"
      ;;
    *)
      echo "  ERROR (${http_code})" >&2
      echo "$payload" >&2
      exit 1
      ;;
  esac
}

apply_rolebinding() {
  local file="$1"
  local name
  name="$(basename "$file" .json)"
  apply_resource \
    "RoleBinding ${name}" \
    POST \
    "/apis/rbac.authorization.k8s.io/v1/namespaces/${NAMESPACE}/rolebindings" \
    "$file"
}

apply_raw() {
  local label="$1"
  local method="$2"
  local path="$3"
  local body="$4"
  local content_type="${5:-application/json}"

  echo "→ ${label}"
  local output http_code payload
  output="$(api_call "$method" "$path" "$body" "$content_type")"
  http_code="${output%%$'\n'*}"
  payload="${output#*$'\n'}"

  case "$http_code" in
    200|201)
      echo "  OK (${http_code})"
      ;;
    409)
      echo "  Ya existe (${http_code}), se continúa"
      ;;
    *)
      echo "  ERROR (${http_code})" >&2
      echo "$payload" >&2
      exit 1
      ;;
  esac
}

create_namespace() {
  if oc get project "${NAMESPACE}" >/dev/null 2>&1; then
    echo "→ Proyecto ${NAMESPACE}"
    echo "  Ya existe, se continúa"
    label_namespace
    return 0
  fi

  echo "→ Namespace ${NAMESPACE} (API Kubernetes)"
  local output http_code payload body
  body="$(render_template "${TEMPLATES_DIR}/namespace.json")"
  output="$(api_call POST "/api/v1/namespaces" "$body")"
  http_code="${output%%$'\n'*}"
  payload="${output#*$'\n'}"

  case "$http_code" in
    200|201)
      echo "  OK (${http_code})"
      ;;
    403)
      echo "  Sin permiso directo (${http_code}), usando ProjectRequest (OpenShift)"
      body="$(render_template "${TEMPLATES_DIR}/projectrequest.json")"
      apply_raw "ProjectRequest ${NAMESPACE}" POST "/apis/project.openshift.io/v1/projectrequests" "$body"
      ;;
    409)
      echo "  Ya existe (${http_code}), se continúa"
      ;;
    *)
      echo "  ERROR (${http_code})" >&2
      echo "$payload" >&2
      exit 1
      ;;
  esac

  label_namespace
}

label_namespace() {
  echo "→ Etiquetas workshop.openshift.io/entorno y proyecto"
  local patch output http_code payload
  patch="{\"metadata\":{\"labels\":{\"workshop.openshift.io/entorno\":\"${ENTORNO}\",\"workshop.openshift.io/proyecto\":\"${PROYECTO}\"}}}"
  output="$(api_call PATCH "/api/v1/namespaces/${NAMESPACE}" "$patch" "application/merge-patch+json")"
  http_code="${output%%$'\n'*}"
  payload="${output#*$'\n'}"

  case "$http_code" in
    200)
      echo "  OK (${http_code})"
      ;;
    403)
      echo "  AVISO (${http_code}): sin permiso para etiquetar el namespace; se continúa"
      echo "  (allow-same-entorno requiere la etiqueta workshop.openshift.io/entorno=${ENTORNO})"
      ;;
    *)
      echo "  ERROR (${http_code})" >&2
      echo "$payload" >&2
      exit 1
      ;;
  esac
}

wait_namespace_active() {
  echo "→ Esperando namespace Active"
  local i
  for i in $(seq 1 60); do
    local phase
    phase="$(oc get namespace "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ "$phase" == "Active" ]]; then
      echo "  OK (Active)"
      return 0
    fi
    sleep 2
  done
  echo "  ERROR: timeout esperando namespace ${NAMESPACE}" >&2
  exit 1
}

echo "Aprovisionando proyecto REST"
echo "  Namespace: ${NAMESPACE}"
echo "  Entorno:   ${ENTORNO}"
echo "  Proyecto:  ${PROYECTO}"
echo "  API:       ${SERVER}"
echo ""

create_namespace

wait_namespace_active

apply_resource \
  "Secret db-credentials-rest" \
  POST \
  "/api/v1/namespaces/${NAMESPACE}/secrets" \
  "${TEMPLATES_DIR}/secret.json"

apply_resource \
  "ConfigMap app-config-rest" \
  POST \
  "/api/v1/namespaces/${NAMESPACE}/configmaps" \
  "${TEMPLATES_DIR}/configmap.json"

apply_resource \
  "NetworkPolicy deny-all-traffic" \
  POST \
  "/apis/networking.k8s.io/v1/namespaces/${NAMESPACE}/networkpolicies" \
  "${TEMPLATES_DIR}/networkpolicy-deny-all.json"

apply_resource \
  "NetworkPolicy allow-same-entorno" \
  POST \
  "/apis/networking.k8s.io/v1/namespaces/${NAMESPACE}/networkpolicies" \
  "${TEMPLATES_DIR}/networkpolicy-allow-same-entorno.json"

if [[ -d "$ROLEBINDINGS_DIR" ]]; then
  shopt -s nullglob
  for rb in "${ROLEBINDINGS_DIR}"/*.json; do
    apply_rolebinding "$rb"
  done
  shopt -u nullglob
fi

echo ""
echo "Recursos en ${NAMESPACE}:"
oc get secret,configmap,networkpolicy,rolebinding -n "$NAMESPACE" 2>/dev/null || true

echo ""
echo "Listo. Namespace: ${NAMESPACE}"
