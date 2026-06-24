## Creación y borrado de recursos vía API REST (OpenShift 4)

Crear y eliminar Namespaces, Secrets, SealedSecrets, ConfigMaps, Deployments, NetworkPolicies, RBAC (Roles, RoleBindings, ClusterRoles), políticas de seguridad y VirtualMachines RHEL 9 usando la API REST de OpenShift/Kubernetes. Incluye script Bash de aprovisionamiento por proyecto y entorno (sin Deployment ni VirtualMachine).

Estructura de este módulo:

```text
workshop-api-rest/
├── README.md                 # este documento
└── rest-automation/          # scripts y plantillas JSON
    ├── provision-project-rest.sh
    ├── destroy-project-rest.sh
    └── templates/
```

---

## 1. Preparación: variables comunes para las llamadas REST

Partimos de que ya estás logueado en el clúster:

```bash
oc login ...
```

Definimos unas variables de entorno para reutilizarlas en los ejemplos:

```bash
export SERVER=$(oc whoami --show-server)
export TOKEN=$(oc whoami -t)
```

En todos los ejemplos de `curl` usaremos:

- `-k`: para ignorar problemas de certificado en entornos de laboratorio.
- Cabecera `Authorization: Bearer $TOKEN` para autenticarnos igual que con `oc`.
- `Content-Type: application/json` para los `POST`/`PUT`.

---

## 2. Namespaces (proyectos)

En OpenShift, la mayoría de usuarios del taller **no son `cluster-admin`**. Crean proyectos con `**ProjectRequest**` (igual que `oc new-project`), no con `POST` directo sobre `/api/v1/namespaces`.

Comprobar permiso antes de empezar:

```bash
oc auth can-i create projectrequests.project.openshift.io
# debe responder: yes
```

### 2.1. Crear un proyecto

Endpoint:

- `POST /apis/project.openshift.io/v1/projectrequests`

```bash
export NS="desarrollo-digital"

curl -k -X POST \
  "$SERVER/apis/project.openshift.io/v1/projectrequests" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    "apiVersion": "project.openshift.io/v1",
    "kind": "ProjectRequest",
    "metadata": { "name": "usuario21-rest" },
    "displayName": "usuario21-rest",
    "description": "Proyecto lab REST"
  }"
```

Equivalente con `oc`:

```bash
oc new-project desarrollo-digital
```

Tras la creación, OpenShift te asigna rol `**admin**` en ese proyecto. Espera a que quede `Active`:

```bash
oc get project "$NS" -w
```

### 2.2. Eliminar un proyecto

Los usuarios normales suelen recibir `403` al hacer `DELETE` sobre `/api/v1/namespaces/<nombre>`. Usa la **Project API** de OpenShift:

Endpoint:

- `DELETE /apis/project.openshift.io/v1/projects/<nombre>`

```bash
curl -k -X DELETE \
  "$SERVER/apis/project.openshift.io/v1/projects/desarrollo-digital" \
  -H "Authorization: Bearer $TOKEN"
```

Equivalente con `oc`:

```bash
oc delete project desarrollo-digital
```

> **Nota**: el borrado es asíncrono; el proyecto pasa a `Terminating` hasta que se eliminan todos los objetos internos.

Si eres `**cluster-admin`**, también puedes usar `DELETE /api/v1/namespaces/<nombre>` (sección 2.3).

### 2.3. Crear Namespace directo (solo `cluster-admin`)

`POST` directo sobre `/api/v1/namespaces` **no funciona** para usuarios con `self-provisioner` (respuesta `403`). Reservado para administradores de clúster o entornos Kubernetes puros:

```bash
curl -k -X POST "$SERVER/api/v1/namespaces" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "v1",
    "kind": "Namespace",
    "metadata": {
      "name": "demo-rest"
    }
  }'
```

---

## 3. Secrets

En este ejemplo trabajaremos dentro del Namespace `demo-rest`. Créalo antes con `ProjectRequest` (sección 2.1) o sustituye el nombre en las URLs.

### 3.1. Crear un Secret genérico (`Opaque`)

Endpoint:

- `POST /api/v1/namespaces/<namespace>/secrets`

Ejemplo:

```bash
curl -k -X POST \
  "$SERVER/api/v1/namespaces/demo-rest/secrets" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "v1",
    "kind": "Secret",
    "metadata": {
      "name": "db-credentials-rest"
    },
    "type": "Opaque",
    "data": {
      "username": "YXBwdXNlcg==",
      "password": "UzNjcjN0UDRzc3cwcmQ="
    }
  }'
```

Los valores en `data` deben ir en **Base64**. En este ejemplo:

- `echo -n "appuser" | base64` → `YXBwdXNlcg==`
- `echo -n "S3cr3tP4ssw0rd" | base64` → `UzNjcjN0UDRzc3cwcmQ=`

Equivalente con `oc`:

```bash
oc create secret generic db-credentials-rest \
  -n demo-rest \
  --from-literal=username=appuser \
  --from-literal=password=S3cr3tP4ssw0rd
```

### 3.2. Listar y borrar un Secret

**Listar** (REST):

```bash
curl -k \
  "$SERVER/api/v1/namespaces/demo-rest/secrets" \
  -H "Authorization: Bearer $TOKEN"
```

**Eliminar** el Secret `db-credentials-rest` (REST):

```bash
curl -k -X DELETE \
  "$SERVER/api/v1/namespaces/demo-rest/secrets/db-credentials-rest" \
  -H "Authorization: Bearer $TOKEN"
```

Equivalente con `oc`:

```bash
oc delete secret db-credentials-rest -n demo-rest
```

---

## 4. ConfigMaps

### 4.1. Crear un ConfigMap

Endpoint:

- `POST /api/v1/namespaces/<namespace>/configmaps`

Ejemplo:

```bash
curl -k -X POST \
  "$SERVER/api/v1/namespaces/demo-rest/configmaps" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "v1",
    "kind": "ConfigMap",
    "metadata": {
      "name": "app-config-rest"
    },
    "data": {
      "APP_MODE": "production",
      "APP_LOG_LEVEL": "info"
    }
  }'
```

Equivalente con `oc`:

```bash
oc create configmap app-config-rest \
  -n demo-rest \
  --from-literal=APP_MODE=production \
  --from-literal=APP_LOG_LEVEL=info
```

### 4.2. Listar y borrar un ConfigMap

**Listar** (REST):

```bash
curl -k \
  "$SERVER/api/v1/namespaces/demo-rest/configmaps" \
  -H "Authorization: Bearer $TOKEN"
```

**Eliminar** el ConfigMap `app-config-rest` (REST):

```bash
curl -k -X DELETE \
  "$SERVER/api/v1/namespaces/demo-rest/configmaps/app-config-rest" \
  -H "Authorization: Bearer $TOKEN"
```

Equivalente con `oc`:

```bash
oc delete configmap app-config-rest -n demo-rest
```

---

## 5. Deployments (apps desplegadas)

En OpenShift 4 conviven `Deployment` (Kubernetes puro, grupo `apps/v1`) y `DeploymentConfig` (recurso clásico de OpenShift). Aquí veremos un ejemplo con `Deployment`.

### 5.1. Crear un Deployment simple

Endpoint:

- `POST /apis/apps/v1/namespaces/<namespace>/deployments`

Ejemplo de Deployment que levanta un Pod con una imagen de demostración de NGINX:

```bash
curl -k -X POST \
  "$SERVER/apis/apps/v1/namespaces/demo-rest/deployments" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "apps/v1",
    "kind": "Deployment",
    "metadata": {
      "name": "nginx-rest"
    },
    "spec": {
      "replicas": 1,
      "selector": {
        "matchLabels": {
          "app": "nginx-rest"
        }
      },
      "template": {
        "metadata": {
          "labels": {
            "app": "nginx-rest"
          }
        },
        "spec": {
          "containers": [
            {
              "name": "nginx",
              "image": "registry.access.redhat.com/hi/nginx:latest",
              "ports": [
                {
                  "containerPort": 8080
                }
              ]
            }
          ]
        }
      }
    }
  }'
```

Equivalente aproximado con `oc`:

```bash
oc create deployment nginx-rest \
  -n demo-rest \
  --image=registry.access.redhat.com/hi/nginx:latest
```

### 5.2. Listar y borrar un Deployment

**Listar** Deployments en el namespace `demo-rest` (REST):

```bash
curl -k \
  "$SERVER/apis/apps/v1/namespaces/demo-rest/deployments" \
  -H "Authorization: Bearer $TOKEN"
```

**Eliminar** el Deployment `nginx-rest` (REST):

```bash
curl -k -X DELETE \
  "$SERVER/apis/apps/v1/namespaces/demo-rest/deployments/nginx-rest" \
  -H "Authorization: Bearer $TOKEN"
```

Equivalente con `oc`:

```bash
oc delete deployment nginx-rest -n demo-rest
```

---

## 6. NetworkPolicies (microsegmentación de red)

Las `NetworkPolicy` controlan qué tráfico de red puede entrar o salir de los Pods. En OpenShift 4 el CNI **OVN-Kubernetes** aplica estas reglas dentro de cada namespace.

Grupo de API: `networking.k8s.io/v1`.

### 6.1. Crear una NetworkPolicy (deny-all)

Política base de **denegación por defecto**: ningún Pod del namespace recibe ni envía tráfico salvo lo que otra política permita explícitamente.

Endpoint:

- `POST /apis/networking.k8s.io/v1/namespaces/<namespace>/networkpolicies`

```bash
curl -k -X POST \
  "$SERVER/apis/networking.k8s.io/v1/namespaces/demo-rest/networkpolicies" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "networking.k8s.io/v1",
    "kind": "NetworkPolicy",
    "metadata": {
      "name": "deny-all-rest"
    },
    "spec": {
      "podSelector": {},
      "policyTypes": ["Ingress"]
    }
  }'
```

Equivalente con `oc`:

```bash
oc apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-rest
  namespace: demo-rest
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF
```

### 6.2. Listar NetworkPolicies

**Listar** todas las políticas del namespace `demo-rest` (REST):

```bash
curl -k \
  "$SERVER/apis/networking.k8s.io/v1/namespaces/demo-rest/networkpolicies" \
  -H "Authorization: Bearer $TOKEN"
```

Equivalente con `oc`:

```bash
oc get networkpolicy -n demo-rest
```

### 6.3. Consultar una NetworkPolicy (GET)

**Obtener** el detalle de `deny-all-rest`:

```bash
curl -k \
  "$SERVER/apis/networking.k8s.io/v1/namespaces/demo-rest/networkpolicies/deny-all-rest" \
  -H "Authorization: Bearer $TOKEN"
```

Equivalente con `oc`:

```bash
oc get networkpolicy deny-all-rest -n demo-rest -o yaml
```

### 6.4. Modificar una NetworkPolicy (PATCH)

Para actualizar reglas o metadatos sin reenviar el objeto completo, usa `PATCH` con `application/merge-patch+json`.

Ejemplo: añadir una etiqueta y permitir tráfico **ingress** entre Pods con label `app: nginx-rest` (complementa la política deny-all del namespace):

```bash
curl -k -X PATCH \
  "$SERVER/apis/networking.k8s.io/v1/namespaces/demo-rest/networkpolicies/deny-all-rest" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/merge-patch+json" \
  -d '{
    "metadata": {
      "labels": { "workshop-rest": "networkpolicy" },
      "annotations": { "workshop/updated": "via-rest-patch" }
    },
    "spec": {
      "ingress": [
        {
          "from": [
            {
              "podSelector": {
                "matchLabels": { "app": "nginx-rest" }
              }
            }
          ]
        }
      ]
    }
  }'
```

Verificar el cambio:

```bash
curl -k \
  "$SERVER/apis/networking.k8s.io/v1/namespaces/demo-rest/networkpolicies/deny-all-rest" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.metadata.labels, .spec.ingress'
```

Equivalente con `oc`:

```bash
oc label networkpolicy deny-all-rest -n demo-rest workshop-rest=networkpolicy
oc annotate networkpolicy deny-all-rest -n demo-rest workshop/updated=via-rest-patch
```

### 6.5. Crear una NetworkPolicy de permiso (allow)

Además del deny-all, puedes definir políticas **positivas** que seleccionan Pods concretos. Ejemplo: permitir ingress TCP/80 solo hacia Pods `app: nginx-rest`:

```bash
curl -k -X POST \
  "$SERVER/apis/networking.k8s.io/v1/namespaces/demo-rest/networkpolicies" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "networking.k8s.io/v1",
    "kind": "NetworkPolicy",
    "metadata": {
      "name": "allow-nginx-rest"
    },
    "spec": {
      "podSelector": {
        "matchLabels": { "app": "nginx-rest" }
      },
      "policyTypes": ["Ingress"],
      "ingress": [
        {
          "from": [
            {
              "podSelector": {
                "matchLabels": { "app": "nginx-rest" }
              }
            }
          ],
          "ports": [
            { "protocol": "TCP", "port": 8080 }
          ]
        }
      ]
    }
  }'
```

Equivalente con `oc`:

```bash
oc apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nginx-rest
  namespace: demo-rest
spec:
  podSelector:
    matchLabels:
      app: nginx-rest
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: nginx-rest
    ports:
    - protocol: TCP
      port: 80
EOF
```

### 6.6. Eliminar NetworkPolicies

**Eliminar** `allow-nginx-rest` y luego `deny-all-rest`:

```bash
curl -k -X DELETE \
  "$SERVER/apis/networking.k8s.io/v1/namespaces/demo-rest/networkpolicies/allow-nginx-rest" \
  -H "Authorization: Bearer $TOKEN"

curl -k -X DELETE \
  "$SERVER/apis/networking.k8s.io/v1/namespaces/demo-rest/networkpolicies/deny-all-rest" \
  -H "Authorization: Bearer $TOKEN"
```

Comprobación (HTTP `404` tras borrar):

```bash
curl -k -s -o /dev/null -w "%{http_code}\n" \
  "$SERVER/apis/networking.k8s.io/v1/namespaces/demo-rest/networkpolicies/deny-all-rest" \
  -H "Authorization: Bearer $TOKEN"
```

Equivalente con `oc`:

```bash
oc delete networkpolicy allow-nginx-rest deny-all-rest -n demo-rest
```

---

## 7. RBAC: Roles, RoleBindings y ClusterRoles

En este capítulo ampliamos la gestión de permisos vía REST. El grupo de API es `rbac.authorization.k8s.io`.

### 7.1. Crear un `Role` en un namespace

Un `Role` define reglas sobre recursos **dentro de un namespace**.

Endpoint:

- `POST /apis/rbac.authorization.k8s.io/v1/namespaces/<namespace>/roles`

Ejemplo: rol que permite leer `ConfigMaps` y `Secrets` (sin exponer datos sensibles fuera del namespace; útil para sidecars o operadores de lectura):

```bash
curl -k -X POST \
  "$SERVER/apis/rbac.authorization.k8s.io/v1/namespaces/demo-rest/roles" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "Role",
    "metadata": {
      "name": "configmap-reader-rest"
    },
    "rules": [
      {
        "apiGroups": [""],
        "resources": ["configmaps"],
        "verbs": ["get", "list", "watch"]
      }
    ]
  }'
```

Equivalente con `oc`:

```bash
oc create role configmap-reader-rest \
  -n demo-rest \
  --verb=get,list,watch \
  --resource=configmaps
```

### 7.2. Crear un `RoleBinding` (enlazar rol a un sujeto)

Un `RoleBinding` asocia un `Role` (o un `ClusterRole` reutilizado localmente) a un sujeto: `User`, `Group` o `ServiceAccount`.

Endpoint:

- `POST /apis/rbac.authorization.k8s.io/v1/namespaces/<namespace>/rolebindings`

Ejemplo: conceder el rol anterior a la `ServiceAccount` `default` del namespace:

```bash
curl -k -X POST \
  "$SERVER/apis/rbac.authorization.k8s.io/v1/namespaces/demo-rest/rolebindings" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "RoleBinding",
    "metadata": {
      "name": "configmap-reader-binding-rest"
    },
    "subjects": [
      {
        "kind": "ServiceAccount",
        "name": "default",
        "namespace": "demo-rest"
      }
    ],
    "roleRef": {
      "apiGroup": "rbac.authorization.k8s.io",
      "kind": "Role",
      "name": "configmap-reader-rest"
    }
  }'
```

Equivalente con `oc`:

```bash
oc create rolebinding configmap-reader-binding-rest \
  -n demo-rest \
  --role=configmap-reader-rest \
  --serviceaccount=demo-rest:default
```

### 7.3. RoleBinding contra un `ClusterRole` predefinido

OpenShift incluye `ClusterRoles` del sistema (`view`, `edit`, `admin`, etc.). Puedes referenciarlos desde un `RoleBinding` **local** para limitar el alcance a un solo namespace.

Ejemplo: dar permiso de solo lectura (`view`) al grupo `desarrolladores` en `demo-rest`:

```bash
curl -k -X POST \
  "$SERVER/apis/rbac.authorization.k8s.io/v1/namespaces/demo-rest/rolebindings" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "RoleBinding",
    "metadata": {
      "name": "view-desarrolladores-rest"
    },
    "subjects": [
      {
        "kind": "Group",
        "name": "desarrolladores",
        "apiGroup": "rbac.authorization.k8s.io"
      }
    ],
    "roleRef": {
      "apiGroup": "rbac.authorization.k8s.io",
      "kind": "ClusterRole",
      "name": "view"
    }
  }'
```

Equivalente con `oc`:

```bash
oc adm policy add-role-to-group view desarrolladores -n demo-rest
```

### 7.4. Crear un `ClusterRole` personalizado

Un `ClusterRole` aplica a nivel de clúster (o se reutiliza desde namespaces mediante bindings).

Endpoint:

- `POST /apis/rbac.authorization.k8s.io/v1/clusterroles`

Ejemplo: rol de clúster que solo permite listar namespaces (auditoría o dashboards):

```bash
curl -k -X POST \
  "$SERVER/apis/rbac.authorization.k8s.io/v1/clusterroles" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "ClusterRole",
    "metadata": {
      "name": "namespace-lister-rest"
    },
    "rules": [
      {
        "apiGroups": [""],
        "resources": ["namespaces"],
        "verbs": ["get", "list", "watch"]
      }
    ]
  }'
```

### 7.5. Crear un `ClusterRoleBinding`

Enlaza un `ClusterRole` a un sujeto con alcance **en todo el clúster**.

Endpoint:

- `POST /apis/rbac.authorization.k8s.io/v1/clusterrolebindings`

```bash
curl -k -X POST \
  "$SERVER/apis/rbac.authorization.k8s.io/v1/clusterrolebindings" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "rbac.authorization.k8s.io/v1",
    "kind": "ClusterRoleBinding",
    "metadata": {
      "name": "namespace-lister-binding-rest"
    },
    "subjects": [
      {
        "kind": "ServiceAccount",
        "name": "auditor",
        "namespace": "demo-rest"
      }
    ],
    "roleRef": {
      "apiGroup": "rbac.authorization.k8s.io",
      "kind": "ClusterRole",
      "name": "namespace-lister-rest"
    }
  }'
```

> **Buena práctica**: evita `ClusterRoleBinding` con roles amplios salvo que el sujeto lo necesite en **todos** los namespaces. Prefiere `RoleBinding` local cuando el permiso es de proyecto.

### 7.6. Listar y borrar RBAC

**Listar RoleBindings** en `demo-rest`:

```bash
curl -k \
  "$SERVER/apis/rbac.authorization.k8s.io/v1/namespaces/demo-rest/rolebindings" \
  -H "Authorization: Bearer $TOKEN"
```

**Eliminar** un `RoleBinding` y su `Role` asociado:

```bash
curl -k -X DELETE \
  "$SERVER/apis/rbac.authorization.k8s.io/v1/namespaces/demo-rest/rolebindings/configmap-reader-binding-rest" \
  -H "Authorization: Bearer $TOKEN"

curl -k -X DELETE \
  "$SERVER/apis/rbac.authorization.k8s.io/v1/namespaces/demo-rest/roles/configmap-reader-rest" \
  -H "Authorization: Bearer $TOKEN"
```

Equivalente con `oc`:

```bash
oc delete rolebinding configmap-reader-binding-rest -n demo-rest
oc delete role configmap-reader-rest -n demo-rest
```

---

## 8. SealedSecrets (secreto cifrado para GitOps)

Un `SealedSecret` (operador Bitnami) permite guardar secretos **cifrados** en Git. Solo el controlador del clúster puede descifrarlos y materializar el `Secret` real en el namespace indicado.

En este clúster el controlador está en `kube-system`:

```bash
oc get deployment sealed-secrets-controller -n kube-system
```

### 8.1. Generar el manifiesto cifrado (fuera de la API REST)

El cifrado se hace con `kubeseal` contra la clave pública del controlador. Los valores cifrados son **específicos del clúster y del namespace**; no se pueden reutilizar en otro entorno.

```bash
# 1) Definir el Secret en texto plano (solo en tu máquina, no commitear)
oc create secret generic db-credentials-sealed \
  -n demo-rest \
  --from-literal=username=appuser \
  --from-literal=password='S3cr3tP4ssw0rd' \
  --dry-run=client -o yaml > /tmp/secret.yaml

# 2) Sellarlo para el namespace demo-rest
kubeseal \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  --format yaml \
  --namespace demo-rest \
  --name db-credentials-sealed \
  < /tmp/secret.yaml > /tmp/sealedsecret.yaml

rm -f /tmp/secret.yaml
```

### 8.2. Crear el SealedSecret vía REST

Endpoint:

- `POST /apis/bitnami.com/v1alpha1/namespaces/<namespace>/sealedsecrets`

Puedes convertir el YAML generado a JSON o enviar el manifiesto con `oc` y replicar la misma estructura:

```bash
curl -k -X POST \
  "$SERVER/apis/bitnami.com/v1alpha1/namespaces/demo-rest/sealedsecrets" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "bitnami.com/v1alpha1",
    "kind": "SealedSecret",
    "metadata": {
      "name": "db-credentials-sealed",
      "namespace": "demo-rest"
    },
    "spec": {
      "encryptedData": {
        "username": "<valor-cifrado-por-kubeseal>",
        "password": "<valor-cifrado-por-kubeseal>"
      },
      "template": {
        "metadata": {
          "name": "db-credentials-sealed",
          "namespace": "demo-rest"
        }
      }
    }
  }'
```

Sustituye `<valor-cifrado-por-kubeseal>` por los campos `encryptedData` reales de `/tmp/sealedsecret.yaml`.

Equivalente con `oc`:

```bash
oc apply -f /tmp/sealedsecret.yaml
```

El operador creará automáticamente el `Secret` `db-credentials-sealed` en `demo-rest`. Compruébalo:

```bash
oc get sealedsecret,secret -n demo-rest | grep db-credentials-sealed
```

### 8.3. Listar y borrar un SealedSecret

**Listar**:

```bash
curl -k \
  "$SERVER/apis/bitnami.com/v1alpha1/namespaces/demo-rest/sealedsecrets" \
  -H "Authorization: Bearer $TOKEN"
```

**Eliminar** (el `Secret` gestionado suele eliminarse en cascada):

```bash
curl -k -X DELETE \
  "$SERVER/apis/bitnami.com/v1alpha1/namespaces/demo-rest/sealedsecrets/db-credentials-sealed" \
  -H "Authorization: Bearer $TOKEN"
```

Equivalente con `oc`:

```bash
oc delete sealedsecret db-credentials-sealed -n demo-rest
```

> **Seguridad**: el `SealedSecret` puede vivir en Git; el `Secret` descifrado no. Limita quién puede leer `secrets` en el namespace mediante RBAC (`view` no incluye acceso a secretos; usa roles dedicados).

---

## 9. Elementos adicionales de seguridad

### 9.1. Comprobar permisos con `SelfSubjectAccessReview`

Antes de automatizar creaciones vía REST, conviene verificar si el token actual tiene permiso para la operación.

Endpoint:

- `POST /apis/authorization.k8s.io/v1/selfsubjectaccessreviews`

```bash
curl -k -X POST \
  "$SERVER/apis/authorization.k8s.io/v1/selfsubjectaccessreviews" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "authorization.k8s.io/v1",
    "kind": "SelfSubjectAccessReview",
    "spec": {
      "resourceAttributes": {
        "namespace": "demo-rest",
        "verb": "create",
        "group": "kubevirt.io",
        "resource": "virtualmachines"
      }
    }
  }'
```

Si `"allowed": true` en la respuesta, el usuario puede crear VMs en ese namespace. Equivalente con `oc`:

```bash
oc auth can-i create virtualmachines.kubevirt.io -n demo-rest
```

### 9.2. Crear una `ServiceAccount` dedicada

Evita reutilizar la SA `default` para automatismos; crea una identidad con permisos mínimos.

Endpoint:

- `POST /api/v1/namespaces/<namespace>/serviceaccounts`

```bash
curl -k -X POST \
  "$SERVER/api/v1/namespaces/demo-rest/serviceaccounts" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "v1",
    "kind": "ServiceAccount",
    "metadata": {
      "name": "pipeline-rest"
    }
  }'
```

Luego enlázala con un `RoleBinding` (sección 7.2) que otorgue solo lo necesario.

### 9.3. ResourceQuota (límite de consumo por namespace)

Útil para evitar que un proyecto agote CPU, memoria o recursos de virtualización.

Endpoint:

- `POST /api/v1/namespaces/<namespace>/resourcequotas`

```bash
curl -k -X POST \
  "$SERVER/api/v1/namespaces/demo-rest/resourcequotas" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "v1",
    "kind": "ResourceQuota",
    "metadata": {
      "name": "demo-rest-quota"
    },
    "spec": {
      "hard": {
        "pods": "10",
        "requests.cpu": "4",
        "requests.memory": "8Gi",
        "limits.cpu": "8",
        "limits.memory": "16Gi"
      }
    }
  }'
```

---

## 10. VirtualMachine RHEL 9 (OpenShift Virtualization)

Este apartado asume **OpenShift Virtualization** instalado. Los ejemplos se validaron contra un clúster OCP 4.20 con imágenes RHEL 9 publicadas en el namespace `openshift-virtualization-os-images`.

### 10.1. Tamaño mínimo verificado para RHEL 9

Consulta los perfiles de instancia disponibles:

```bash
oc get virtualmachineclusterinstancetype \
  -o custom-columns=NAME:.metadata.name,CPU:.spec.cpu.guest,MEMORY:.spec.memory.guest
```

Las VMs RHEL 9 del clúster exigen al menos **1,5 GiB** de RAM (`1610612736` bytes en la anotación `vm.kubevirt.io/validations`). Por tanto:


| Instance type  | CPU   | Memoria | ¿Válido para RHEL 9?        |
| -------------- | ----- | ------- | --------------------------- |
| `u1.nano`      | 1     | 512Mi   | No                          |
| `u1.micro`     | 1     | 1Gi     | No                          |
| `**u1.small`** | **1** | **2Gi** | **Sí (mínimo recomendado)** |


Perfil de SO recomendado: `rhel.9` (`VirtualMachineClusterPreference`).  
Origen del disco: `DataSource` `rhel9` en `openshift-virtualization-os-images`.

```bash
oc get datasource rhel9 -n openshift-virtualization-os-images
oc get virtualmachineclusterpreference rhel.9
```

### 10.2. Crear una VM RHEL 9 mínima vía REST (enfoque con instance type)

Endpoint:

- `POST /apis/kubevirt.io/v1/namespaces/<namespace>/virtualmachines`

Usamos `runStrategy: Halted` para que la VM se cree pero **no arranque** automáticamente (ideal para laboratorio). La API de KubeVirt expande `instancetype` y `preference` al procesar la petición.

```bash
curl -k -X POST \
  "$SERVER/apis/kubevirt.io/v1/namespaces/demo-rest/virtualmachines" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "kubevirt.io/v1",
    "kind": "VirtualMachine",
    "metadata": {
      "name": "rhel9-rest-demo"
    },
    "spec": {
      "runStrategy": "Halted",
      "instancetype": {
        "kind": "VirtualMachineClusterInstancetype",
        "name": "u1.small"
      },
      "preference": {
        "kind": "VirtualMachineClusterPreference",
        "name": "rhel.9"
      },
      "dataVolumeTemplates": [
        {
          "metadata": {
            "name": "rhel9-rest-demo"
          },
          "spec": {
            "sourceRef": {
              "kind": "DataSource",
              "name": "rhel9",
              "namespace": "openshift-virtualization-os-images"
            },
            "storage": {
              "resources": {
                "requests": {
                  "storage": "30Gi"
                }
              }
            }
          }
        }
      ]
    }
  }'
```

### 10.3. Alternativa: manifiesto explícito (template completo)

Si necesitas control total del hardware virtual (validado con `oc apply --dry-run=server` en el clúster):

```bash
curl -k -X POST \
  "$SERVER/apis/kubevirt.io/v1/namespaces/demo-rest/virtualmachines" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "apiVersion": "kubevirt.io/v1",
    "kind": "VirtualMachine",
    "metadata": {
      "name": "rhel9-rest-demo"
    },
    "spec": {
      "runStrategy": "Halted",
      "dataVolumeTemplates": [
        {
          "metadata": {
            "name": "rhel9-rest-demo"
          },
          "spec": {
            "sourceRef": {
              "kind": "DataSource",
              "name": "rhel9",
              "namespace": "openshift-virtualization-os-images"
            },
            "storage": {
              "resources": {
                "requests": {
                  "storage": "30Gi"
                }
              }
            }
          }
        }
      ],
      "template": {
        "metadata": {
          "labels": {
            "kubevirt.io/domain": "rhel9-rest-demo"
          }
        },
        "spec": {
          "architecture": "amd64",
          "domain": {
            "cpu": {
              "cores": 1,
              "sockets": 1,
              "threads": 1
            },
            "devices": {
              "disks": [
                {
                  "name": "rootdisk",
                  "bootOrder": 1,
                  "disk": { "bus": "virtio" }
                },
                {
                  "name": "cloudinitdisk",
                  "disk": { "bus": "virtio" }
                }
              ],
              "interfaces": [
                {
                  "name": "default",
                  "masquerade": {},
                  "model": "virtio"
                }
              ],
              "rng": {}
            },
            "features": {
              "smm": { "enabled": true }
            },
            "firmware": {
              "bootloader": { "efi": {} }
            },
            "machine": {
              "type": "pc-q35-rhel9.6.0"
            },
            "memory": {
              "guest": "2Gi"
            }
          },
          "networks": [
            { "name": "default", "pod": {} }
          ],
          "volumes": [
            {
              "name": "rootdisk",
              "dataVolume": { "name": "rhel9-rest-demo" }
            },
            {
              "name": "cloudinitdisk",
              "cloudInitNoCloud": {
                "userData": "#cloud-config\nuser: cloud-user\npassword: changeme\nchpasswd: { expire: False }\n"
              }
            }
          ]
        }
      }
    }
  }'
```

> Cambia la contraseña de `cloud-user` antes de arrancar la VM en entornos reales.

### 10.4. Arrancar, consultar y eliminar la VM

**Consultar estado** (REST):

```bash
curl -k \
  "$SERVER/apis/kubevirt.io/v1/namespaces/demo-rest/virtualmachines/rhel9-rest-demo" \
  -H "Authorization: Bearer $TOKEN"
```

**Arrancar** la VM (cambiar `runStrategy` a `Always` con `PATCH`):

```bash
curl -k -X PATCH \
  "$SERVER/apis/kubevirt.io/v1/namespaces/demo-rest/virtualmachines/rhel9-rest-demo" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/merge-patch+json" \
  -d '{"spec":{"runStrategy":"Always"}}'
```

Equivalente con `oc`:

```bash
oc patch vm rhel9-rest-demo -n demo-rest --type merge -p '{"spec":{"runStrategy":"Always"}}'
```

**Eliminar** la VM y su `DataVolume` asociado:

```bash
curl -k -X DELETE \
  "$SERVER/apis/kubevirt.io/v1/namespaces/demo-rest/virtualmachines/rhel9-rest-demo" \
  -H "Authorization: Bearer $TOKEN"
```

Equivalente con `oc`:

```bash
oc delete vm rhel9-rest-demo -n demo-rest
```

---

## 11. Automatización con Bash (proyecto + entorno)

Los ejemplos `curl` de las secciones anteriores se pueden encadenar en un script que reciba **proyecto** y **entorno**, sustituya variables en plantillas JSON y cree los recursos base del namespace en orden.

```text
rest-automation/
├── provision-project-rest.sh    # crea proyecto + recursos
├── destroy-project-rest.sh      # elimina en orden inverso
└── templates/
    ├── namespace.json           # solo cluster-admin
    ├── projectrequest.json      # usuarios OpenShift (self-provisioner)
    ├── secret.json
    ├── configmap.json
    ├── networkpolicy-deny-all.json
    ├── networkpolicy-allow-same-entorno.json
    └── rolebindings/
        └── view-sdi.json
```

Los scripts y plantillas viven en la carpeta `rest-automation/` de este módulo.

### 11.1. Uso rápido

Requisito previo: `oc login` en el clúster.

```bash
cd rest-automation

# Ejemplo: usuario user21, entorno qa → namespace qa-usuario21
./provision-project-rest.sh usuario21 qa

# Limpiar todo
./destroy-project-rest.sh usuario21 qa
```

Convención de nombres: el namespace se forma como `**<entorno>-<proyecto>**` (ej. `qa-usuario21`).

**Creación del proyecto:** el script intenta primero `POST /api/v1/namespaces`. Si recibe `403` (usuario normal en OpenShift), usa automáticamente `ProjectRequest` (sección 2.1). Luego intenta aplicar etiquetas `workshop.openshift.io/entorno` y `workshop.openshift.io/proyecto`; si el usuario no puede parchear el namespace, muestra un aviso y continúa.

**Eliminación:** si `DELETE /api/v1/namespaces` devuelve `403`, el script de destroy usa `DELETE /apis/project.openshift.io/v1/projects/<nombre>` (sección 2.2).

Etiquetas deseadas en el namespace:

- `workshop.openshift.io/entorno: <entorno>`
- `workshop.openshift.io/proyecto: <proyecto>`

La `NetworkPolicy` `allow-same-entorno` permite ingress desde **otros namespaces con la misma etiqueta de entorno**, alineado con el patrón del workshop de ArgoCD (`[../automatizacion-namespace/workshop-namespaces-argocd/](../automatizacion-namespace/workshop-namespaces-argocd/)`).

### 11.2. Paso a paso: cómo funciona el script

**1. Parámetros de entrada**

```bash
PROYECTO="$1"    # ej. demo-app
ENTORNO="$2"     # ej. desarrollo
NAMESPACE="${ENTORNO}-${PROYECTO}"
```

**2. Credenciales REST desde `oc`**

El script reutiliza la sesión activa:

```bash
SERVER="$(oc whoami --show-server)"
TOKEN="$(oc whoami -t)"
```

**3. Renderizado de plantillas**

Cada JSON en `templates/` usa marcadores `__NAMESPACE__`, `__ENTORNO__` y `__PROYECTO__`. La función `render_template` los sustituye con `sed` antes de enviar el cuerpo al API.

**4. Llamada REST genérica**

`apply_resource` hace `POST` con `curl`, cabecera `Authorization: Bearer $TOKEN` y valida el código HTTP:

- `201` / `200` → éxito
- `409` → el recurso ya existe (idempotencia parcial)
- otro → aborta con error

**5. Orden de creación**


| Paso | Recurso                                        | Endpoint REST                                     |
| ---- | ---------------------------------------------- | ------------------------------------------------- |
| 1    | Namespace o ProjectRequest                     | `POST /api/v1/namespaces` o `.../projectrequests` |
| 2    | *(espera Active)*                              | `oc get project`                                  |
| 3    | Secret                                         | `POST .../secrets`                                |
| 4    | ConfigMap                                      | `POST .../configmaps`                             |
| 5    | NetworkPolicy deny-all                         | `POST .../networkpolicies`                        |
| 6    | NetworkPolicy allow-same-entorno               | `POST .../networkpolicies`                        |
| 7    | RoleBindings (`templates/rolebindings/*.json`) | `POST .../rolebindings`                           |


**6. Verificación final**

El script lista con `oc get` los recursos creados en el namespace.

### 11.3. Resultado de prueba en clúster

Ejecución validada con usuario `**user21`** (sin `cluster-admin`), entorno `**qa`**, proyecto `**usuario21`**:

```bash
./provision-project-rest.sh usuario21 qa
```

Namespace creado: `**qa-usuario21**`. Todos los `POST` de recursos devolvieron **201**:

- ProjectRequest `qa-usuario21` (usuario dueño con rol `admin`)
- Secret `db-credentials-rest`
- ConfigMap `app-config-rest`
- NetworkPolicy `deny-all-traffic` y `allow-same-entorno`
- RoleBinding `view-sdi` → ClusterRole `view` para el grupo `SDI`

### 11.4. Agregar más RoleBindings

Los bindings no van hardcodeados en el script: se leen de `templates/rolebindings/*.json`. Para añadir otro, crea un archivo JSON nuevo en esa carpeta.

Ejemplo: dar rol `edit` al grupo `infrati` en el mismo namespace:

```bash
cd rest-automation
cat > templates/rolebindings/edit-infrati.json <<'EOF'
{
  "apiVersion": "rbac.authorization.k8s.io/v1",
  "kind": "RoleBinding",
  "metadata": {
    "name": "edit-infrati"
  },
  "subjects": [
    {
      "kind": "Group",
      "name": "infrati",
      "apiGroup": "rbac.authorization.k8s.io"
    }
  ],
  "roleRef": {
    "apiGroup": "rbac.authorization.k8s.io",
    "kind": "ClusterRole",
    "name": "edit"
  }
}
EOF
```

Al volver a ejecutar `./provision-project-rest.sh demo-app desarrollo`, el script aplicará **todos** los `.json` de `rolebindings/` (incluido el nuevo). Si el binding ya existía, recibirás `409` y el script continuará.

Para eliminar bindings adicionales, `destroy-project-rest.sh` recorre la misma carpeta y borra cada uno antes de eliminar el namespace.

> **Nota**: el `metadata.name` del JSON debe ser único por namespace. Usa nombres descriptivos (`view-sdi`, `edit-infrati`, `admin-ops`, etc.).

### 11.5. Personalizar otros recursos

Para cambiar CPU, imagen, cuotas o políticas de red:

1. Edita el JSON correspondiente en `templates/`.
2. Vuelve a ejecutar el script sobre un namespace nuevo, o elimina el recurso concreto y créalo de nuevo.

Si necesitas variaciones por entorno (por ejemplo, cuotas distintas en `qa` vs `produccion`), puedes crear subcarpetas bajo `rest-automation/templates/` (p. ej. `templates/desarrollo/`, `templates/qa/`) y ajustar el script para elegir la carpeta según `$ENTORNO` (extensión opcional del laboratorio).

---

## 12. Orden sugerido para el laboratorio

Flujo para **usuarios con permiso de crear proyectos** en OpenShift (`self-provisioner`). Creas tu propio namespace/proyecto vía REST y luego los recursos dentro de él.

### Ejemplo: user21, proyecto digital, entorno desarrollo

```bash
oc login ...    # usuario sin cluster-admin, ej. user21
export SERVER=$(oc whoami --show-server)
export TOKEN=$(oc whoami -t)
export PROYECTO=digital
export ENTORNO=desarrollo
export NS="${ENTORNO}-${PROYECTO}"    # → desarrollo-digital
```

Comprobar que puedes solicitar proyectos:

```bash
oc auth can-i create projectrequests.project.openshift.io
# debe responder: yes
```

### Opción A — Paso a paso con curl

1. **Crear el proyecto** `$NS` con `ProjectRequest` (sección 2.1):
  ```bash
   curl -k -X POST "$SERVER/apis/project.openshift.io/v1/projectrequests" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d "{\"apiVersion\":\"project.openshift.io/v1\",\"kind\":\"ProjectRequest\",\"metadata\":{\"name\":\"$NS\"},\"displayName\":\"$NS\"}"

   oc get project "$NS" -w
  ```
  > Solo si eres `cluster-admin`: `POST /api/v1/namespaces` (sección 2.3).
2. **Secret** `db-credentials-rest` (sección 3).
3. **ConfigMap** `app-config-rest` (sección 4).
4. **Deployment** `nginx-rest` (sección 5).
5. **NetworkPolicies** `deny-all-traffic` y `allow-same-entorno` (sección 6).
6. **RoleBinding** `view` para el grupo `SDI` (sección 7.3).
7. **Verificar** con `oc get all,networkpolicy,rolebinding -n $NS`.
8. **Limpiar**: eliminar recursos vía REST `DELETE` (secciones 3–7) y el proyecto con la Project API (sección 2.2).

En los ejemplos del documento sustituye `demo-rest` por `$NS`.

### Opción B — Script de automatización (sección 11)

```bash
cd rest-automation
./provision-project-rest.sh digital desarrollo
# Namespace: desarrollo-digital
```

El script detecta si debes usar `ProjectRequest` en lugar de `POST` directo al namespace. Después añade el **Deployment** manualmente (sección 5). Para limpiar:

```bash
./destroy-project-rest.sh digital desarrollo
```

---

