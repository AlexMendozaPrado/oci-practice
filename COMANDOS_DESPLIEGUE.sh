#!/bin/bash
# =============================================================================
# COMANDOS PARA DESPLIEGUE EN OCI
# Ejecutar en tu máquina local con OCI CLI configurado
# =============================================================================

# -----------------------------------------------------------------------------
# PASO 0: CONFIGURAR VARIABLES (EDITAR ESTOS VALORES)
# -----------------------------------------------------------------------------
export COMPARTMENT_OCID="ocid1.compartment.oc1..TU_COMPARTMENT"
export TENANCY_OCID="ocid1.tenancy.oc1..TU_TENANCY"
export USER_OCID="ocid1.user.oc1..TU_USER"
export REGION="sa-saopaulo-1"  # Cambiar a tu región
export TENANCY_NAMESPACE=""    # Se obtiene automáticamente abajo

# -----------------------------------------------------------------------------
# PASO 1: VERIFICAR OCI CLI
# -----------------------------------------------------------------------------
echo "=== Verificando OCI CLI ==="
oci --version
oci iam region list --output table

# Obtener namespace del tenancy
TENANCY_NAMESPACE=$(oci os ns get --query 'data' --raw-output)
echo "Namespace: $TENANCY_NAMESPACE"

# -----------------------------------------------------------------------------
# PASO 2: CLONAR REPOSITORIO (si no lo tienes)
# -----------------------------------------------------------------------------
# git clone https://github.com/AlexMendozaPrado/oci-practice.git
# cd oci-practice
# git checkout claude/implement-plan-features-BqG16

# -----------------------------------------------------------------------------
# PASO 3: EJECUTAR TERRAFORM
# -----------------------------------------------------------------------------
echo "=== Ejecutando Terraform ==="
cd mtdrworkshop/terraform

terraform init

terraform plan \
  -var="ociCompartmentOcid=$COMPARTMENT_OCID" \
  -var="ociTenancyOcid=$TENANCY_OCID" \
  -var="ociUserOcid=$USER_OCID" \
  -var="ociRegionIdentifier=$REGION"

# Descomentar cuando estés listo para aplicar:
# terraform apply \
#   -var="ociCompartmentOcid=$COMPARTMENT_OCID" \
#   -var="ociTenancyOcid=$TENANCY_OCID" \
#   -var="ociUserOcid=$USER_OCID" \
#   -var="ociRegionIdentifier=$REGION"

# -----------------------------------------------------------------------------
# PASO 4: CONFIGURAR DOCKER REGISTRY (OCIR)
# -----------------------------------------------------------------------------
echo "=== Configurando OCIR ==="
export DOCKER_REGISTRY="${REGION}.ocir.io/${TENANCY_NAMESPACE}/mtdr"

# Login a OCIR (usar Auth Token como password)
# Generar Auth Token en: OCI Console > Identity > Users > Tu User > Auth Tokens
docker login ${REGION}.ocir.io
# Username: <namespace>/<username>  ej: tenancyname/oracleidentitycloudservice/user@email.com
# Password: <tu-auth-token>

# -----------------------------------------------------------------------------
# PASO 5: BUILD Y PUSH BACKEND
# -----------------------------------------------------------------------------
echo "=== Build y Push Backend ==="
cd ../backend

# Build con Maven (opcional si usas multi-stage)
# mvn clean package -DskipTests

# Build imagen Docker
docker build -t $DOCKER_REGISTRY/todolistapp-helidon-se:0.1 -f src/main/docker/Dockerfile .

# Push a OCIR
docker push $DOCKER_REGISTRY/todolistapp-helidon-se:0.1

# -----------------------------------------------------------------------------
# PASO 6: BUILD Y PUSH FRONTEND
# -----------------------------------------------------------------------------
echo "=== Build y Push Frontend ==="
cd ../frontend

# Obtener URL del API Gateway después de terraform apply
# API_GATEWAY_URL="https://xxxx.apigateway.${REGION}.oci.customer-oci.com"

# Build imagen Docker
docker build -t $DOCKER_REGISTRY/frontend:1.0 \
  --build-arg REACT_APP_API_URL=${API_GATEWAY_URL}/todolist .

# Push a OCIR
docker push $DOCKER_REGISTRY/frontend:1.0

# -----------------------------------------------------------------------------
# PASO 7: CONFIGURAR KUBECTL
# -----------------------------------------------------------------------------
echo "=== Configurando kubectl ==="
# Obtener CLUSTER_OCID del output de Terraform o de OCI Console
# CLUSTER_OCID="ocid1.cluster.oc1..."

oci ce cluster create-kubeconfig \
  --cluster-id $CLUSTER_OCID \
  --file $HOME/.kube/config \
  --region $REGION \
  --token-version 2.0.0

kubectl get nodes

# -----------------------------------------------------------------------------
# PASO 8: CREAR NAMESPACE Y SECRETS
# -----------------------------------------------------------------------------
echo "=== Creando namespace y secrets ==="
kubectl create namespace mtdrworkshop

# Descargar wallet de ATP
# ATP_OCID="ocid1.autonomousdatabase.oc1..."
oci db autonomous-database generate-wallet \
  --autonomous-database-id $ATP_OCID \
  --file wallet.zip \
  --password "WalletPassword123#"

unzip wallet.zip -d wallet/

# Crear secrets
kubectl create secret generic dbuser \
  --from-literal=dbpassword="TuPasswordDB123#" \
  -n mtdrworkshop

kubectl create secret generic db-wallet-secret \
  --from-file=wallet/ \
  -n mtdrworkshop

# -----------------------------------------------------------------------------
# PASO 9: DESPLEGAR BACKEND
# -----------------------------------------------------------------------------
echo "=== Desplegando Backend ==="
cd ../backend/src/main/k8s

# Obtener nombre de PDB de ATP (normalmente es el nombre de la BD + _tp, _tpurgent, etc.)
export TODO_PDB_NAME="mtdrdb_tp"  # Ajustar según tu BD
export OCI_REGION=$REGION

# Crear archivo final con variables sustituidas
sed -e "s|%DOCKER_REGISTRY%|$DOCKER_REGISTRY|g" \
    -e "s|%TODO_PDB_NAME%|$TODO_PDB_NAME|g" \
    -e "s|%OCI_REGION%|$OCI_REGION|g" \
    todolistapp-helidon-se-deployment.yaml > backend-final.yaml

kubectl apply -f backend-final.yaml -n mtdrworkshop

# -----------------------------------------------------------------------------
# PASO 10: DESPLEGAR FRONTEND
# -----------------------------------------------------------------------------
echo "=== Desplegando Frontend ==="
cd ../../../frontend/k8s

sed "s|%DOCKER_REGISTRY%|$DOCKER_REGISTRY|g" \
    frontend-deployment.yaml > frontend-final.yaml

kubectl apply -f frontend-final.yaml -n mtdrworkshop

# -----------------------------------------------------------------------------
# PASO 11: VERIFICAR DESPLIEGUE
# -----------------------------------------------------------------------------
echo "=== Verificando despliegue ==="
kubectl get all -n mtdrworkshop
kubectl get pods -n mtdrworkshop -w

# Ver logs
# kubectl logs -f deployment/todolistapp-helidon-se-deployment -n mtdrworkshop
# kubectl logs -f deployment/frontend-deployment -n mtdrworkshop

# -----------------------------------------------------------------------------
# PASO 12: PROBAR API
# -----------------------------------------------------------------------------
echo "=== Probando API ==="
# Después de configurar API Gateway en OCI Console:
# curl -X GET https://<api-gateway-url>/todolist
# curl -X POST https://<api-gateway-url>/todolist \
#   -H "Content-Type: application/json" \
#   -d '{"description": "Test desde curl"}'
