#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso: destroy-project-rest.sh <proyecto> <entorno>

Elimina los recursos creados por provision-project-rest.sh y el namespace.

Ejemplo: destroy-project-rest.sh demo-app desarrollo
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 2 ]]; then
  usage
  exit "${1:+0}"
fi

PROYECTO="$1"
ENTORNO="$2"

NAMESPACE="${ENTORNO}-${PROYECTO}"

if ! oc whoami >/dev/null 2>&1; then
  echo "ERROR: ejecuta 'oc login' antes de continuar." >&2
  exit 1
fi

SERVER="$(oc whoami --show-server)"
TOKEN="$(oc whoami -t)"

delete_resource() {
  local label="$1"
  local path="$2"

  echo "→ Eliminar ${label}"
  local code
  code="$(curl -ks -o /dev/null -w "%{http_code}" -X DELETE \
    "${SERVER}${path}" \
    -H "Authorization: Bearer ${TOKEN}")"

  case "$code" in
    200|202|404)
      echo "  OK (${code})"
      ;;
    403)
      echo "  AVISO (${code}): sin acceso al recurso, se continúa"
      ;;
    *)
      echo "  ERROR (${code})" >&2
      exit 1
      ;;
  esac
}

echo "Eliminando proyecto REST: ${NAMESPACE}"
echo ""

delete_resource "NetworkPolicy allow-same-entorno" \
  "/apis/networking.k8s.io/v1/namespaces/${NAMESPACE}/networkpolicies/allow-same-entorno"

delete_resource "NetworkPolicy deny-all-traffic" \
  "/apis/networking.k8s.io/v1/namespaces/${NAMESPACE}/networkpolicies/deny-all-traffic"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLEBINDINGS_DIR="${SCRIPT_DIR}/templates/rolebindings"
if [[ -d "$ROLEBINDINGS_DIR" ]]; then
  shopt -s nullglob
  for f in "${ROLEBINDINGS_DIR}"/*.json; do
    rb="$(basename "$f" .json)"
    delete_resource "RoleBinding ${rb}" \
      "/apis/rbac.authorization.k8s.io/v1/namespaces/${NAMESPACE}/rolebindings/${rb}"
  done
  shopt -u nullglob
fi

delete_resource "ConfigMap app-config-rest" \
  "/api/v1/namespaces/${NAMESPACE}/configmaps/app-config-rest"

delete_resource "Secret db-credentials-rest" \
  "/api/v1/namespaces/${NAMESPACE}/secrets/db-credentials-rest"

delete_namespace() {
  echo "→ Eliminar proyecto/namespace ${NAMESPACE}"
  local code
  code="$(curl -ks -o /dev/null -w "%{http_code}" -X DELETE \
    "${SERVER}/api/v1/namespaces/${NAMESPACE}" \
    -H "Authorization: Bearer ${TOKEN}")"

  case "$code" in
    200|202|404)
      echo "  OK (${code})"
      ;;
    403)
      echo "  Sin permiso directo (${code}), usando Project API (OpenShift)"
      code="$(curl -ks -o /dev/null -w "%{http_code}" -X DELETE \
        "${SERVER}/apis/project.openshift.io/v1/projects/${NAMESPACE}" \
        -H "Authorization: Bearer ${TOKEN}")"
      case "$code" in
        200|202|404)
          echo "  OK (${code})"
          ;;
        *)
          echo "  ERROR (${code})" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "  ERROR (${code})" >&2
      exit 1
      ;;
  esac
}

delete_namespace

echo ""
echo "Eliminación completada."
