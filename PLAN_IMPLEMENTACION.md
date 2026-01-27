# Plan de Implementacion: Containerizacion y Despliegue en OCI

## Resumen
Contenerizar la aplicacion MyToDo React (frontend + backend) y desplegarla en Oracle Cloud Infrastructure usando OKE (Kubernetes).

---

## Fase 1: Preparacion de Dockerfiles

### 1.1 Backend (Java/Helidon) - Mejorar Dockerfile existente
**Archivo:** `mtdrworkshop/backend/src/main/docker/Dockerfile`

**Dockerfile mejorado con multi-stage build:**

```dockerfile
# Stage 1: Build
FROM maven:3.8-openjdk-11 AS builder
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn package -DskipTests

# Stage 2: Runtime
FROM openjdk:11-jre-slim
WORKDIR /app
COPY --from=builder /app/target/libs ./libs
COPY --from=builder /app/target/todolistapp-helidon-se.jar ./app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### 1.2 Frontend (React) - Crear nuevo Dockerfile
**Archivo a crear:** `mtdrworkshop/frontend/Dockerfile`

```dockerfile
# Stage 1: Build
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
ARG REACT_APP_API_URL
ENV REACT_APP_API_URL=$REACT_APP_API_URL
RUN npm run build

# Stage 2: Serve
FROM nginx:alpine
COPY --from=builder /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### 1.3 Archivo nginx.conf para Frontend
**Archivo a crear:** `mtdrworkshop/frontend/nginx.conf`

```nginx
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /health {
        return 200 'healthy';
        add_header Content-Type text/plain;
    }
}
```

### 1.4 Archivo .dockerignore para Frontend
**Archivo a crear:** `mtdrworkshop/frontend/.dockerignore`

```
node_modules
build
.git
*.md
.env.local
```

---

## Fase 2: Configuracion de Kubernetes

### 2.1 Manifiestos K8s para Frontend
**Archivo a crear:** `mtdrworkshop/frontend/k8s/frontend-deployment.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: frontend
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: %DOCKER_REGISTRY%/frontend:1.0
        imagePullPolicy: Always
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 5
        readinessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 3
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
```

### 2.2 Actualizar Backend - Habilitar health checks
**Archivo:** `mtdrworkshop/backend/src/main/k8s/todolistapp-helidon-se-deployment.yaml`

Descomentar las lineas de livenessProbe y readinessProbe.

---

## Fase 3: Configuracion de OCI

### 3.1 Pre-requisitos en OCI
1. Tenancy configurado con:
   - Compartment para el proyecto
   - Usuario con permisos adecuados
   - OCI CLI configurado localmente (`oci setup config`)

2. Verificar OCI CLI:
```bash
oci iam region list
```

### 3.2 Ejecutar Terraform
```bash
cd mtdrworkshop/terraform

# Inicializar
terraform init

# Ver plan
terraform plan -var="ociCompartmentOcid=<COMPARTMENT_OCID>" \
               -var="ociTenancyOcid=<TENANCY_OCID>" \
               -var="ociUserOcid=<USER_OCID>" \
               -var="ociRegionIdentifier=<REGION>"

# Aplicar
terraform apply
```

**Recursos creados:**
- VCN (10.0.0.0/16) con subnets
- OKE Cluster (Kubernetes v1.23.4)
- Node Pool (3 x VM.Standard.E2.1)
- Autonomous Database (1 OCPU, 1 TB)
- API Gateway (publico)
- Internet Gateway, NAT Gateway, Service Gateway

---

## Fase 4: Build y Push de Imagenes

### 4.1 Configurar OCIR (Container Registry)

```bash
# Obtener namespace
oci os ns get

# Login a OCIR (usar Auth Token como password)
docker login <region>.ocir.io

# Ejemplo:
# docker login sa-saopaulo-1.ocir.io
# Username: <tenancy-namespace>/<username>
# Password: <auth-token>

# Configurar variable
export DOCKER_REGISTRY=<region>.ocir.io/<namespace>/mtdr
```

### 4.2 Build y Push Backend
```bash
cd mtdrworkshop/backend

# Build con Maven
mvn clean package -DskipTests

# Build imagen Docker
docker build -t $DOCKER_REGISTRY/backend:1.0 -f src/main/docker/Dockerfile .

# Push a OCIR
docker push $DOCKER_REGISTRY/backend:1.0
```

### 4.3 Build y Push Frontend
```bash
cd mtdrworkshop/frontend

# Build imagen Docker con API URL
docker build -t $DOCKER_REGISTRY/frontend:1.0 \
  --build-arg REACT_APP_API_URL=https://<api-gateway-url>/todolist .

# Push a OCIR
docker push $DOCKER_REGISTRY/frontend:1.0
```

---

## Fase 5: Configuracion de Base de Datos

### 5.1 Obtener Wallet de ATP
```bash
# Via OCI CLI
oci db autonomous-database generate-wallet \
  --autonomous-database-id <ATP_OCID> \
  --file wallet.zip \
  --password <wallet_password>

# Descomprimir
unzip wallet.zip -d wallet/
```

### 5.2 Configurar kubectl
```bash
# Obtener kubeconfig del cluster OKE
oci ce cluster create-kubeconfig \
  --cluster-id <CLUSTER_OCID> \
  --file $HOME/.kube/config \
  --region <REGION> \
  --token-version 2.0.0

# Verificar conexion
kubectl get nodes
```

### 5.3 Crear Secrets en Kubernetes
```bash
# Crear namespace
kubectl create namespace mtdrworkshop

# Secret para password de BD
kubectl create secret generic dbuser \
  --from-literal=dbpassword=<DB_PASSWORD> \
  -n mtdrworkshop

# Secret para wallet
kubectl create secret generic db-wallet-secret \
  --from-file=wallet/ \
  -n mtdrworkshop

# Verificar secrets
kubectl get secrets -n mtdrworkshop
```

### 5.4 Crear tabla y usuario en ATP

Conectar via SQL Developer o Cloud Shell:

```sql
-- Crear tabla
CREATE TABLE todoitem (
    id NUMBER GENERATED ALWAYS AS IDENTITY,
    description VARCHAR2(32000),
    creation_ts TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    done NUMBER(1,0),
    PRIMARY KEY (id)
);

-- Crear usuario de la aplicacion
CREATE USER TODOUSER IDENTIFIED BY "<password>";
GRANT CONNECT, RESOURCE TO TODOUSER;
GRANT UNLIMITED TABLESPACE TO TODOUSER;
GRANT ALL PRIVILEGES ON todoitem TO TODOUSER;
```

---

## Fase 6: Despliegue en OKE

### 6.1 Preparar manifiestos
```bash
# Backend - sustituir variables
export DOCKER_REGISTRY=<region>.ocir.io/<namespace>/mtdr
export TODO_PDB_NAME=<database_name>
export OCI_REGION=<region>

cd mtdrworkshop/backend/src/main/k8s

# Sustituir placeholders en el YAML
sed -e "s|%DOCKER_REGISTRY%|$DOCKER_REGISTRY|g" \
    -e "s|%TODO_PDB_NAME%|$TODO_PDB_NAME|g" \
    -e "s|%OCI_REGION%|$OCI_REGION|g" \
    todolistapp-helidon-se-deployment.yaml > deployment-final.yaml
```

### 6.2 Desplegar Backend
```bash
kubectl apply -f deployment-final.yaml -n mtdrworkshop

# Verificar
kubectl get pods -n mtdrworkshop
kubectl get svc -n mtdrworkshop
```

### 6.3 Desplegar Frontend
```bash
cd mtdrworkshop/frontend/k8s

# Sustituir variables
sed "s|%DOCKER_REGISTRY%|$DOCKER_REGISTRY|g" \
    frontend-deployment.yaml > frontend-final.yaml

kubectl apply -f frontend-final.yaml -n mtdrworkshop
```

### 6.4 Verificar despliegue
```bash
# Ver todos los recursos
kubectl get all -n mtdrworkshop

# Ver logs del backend
kubectl logs -f deployment/todolistapp-helidon-se-deployment -n mtdrworkshop

# Ver logs del frontend
kubectl logs -f deployment/frontend-deployment -n mtdrworkshop
```

---

## Fase 7: Configuracion de API Gateway

### 7.1 Crear Deployment en API Gateway (OCI Console)

1. Ir a: OCI Console > Developer Services > API Gateway
2. Seleccionar el gateway "todolist" creado por Terraform
3. Crear nuevo Deployment:
   - Name: `todolist-api`
   - Path Prefix: `/`

4. Agregar rutas:

| Path | Methods | Backend Type | Backend |
|------|---------|--------------|---------|
| /todolist | GET, POST | HTTP | http://<backend-lb-ip>:80/todolist |
| /todolist/{id} | GET, PUT, DELETE | HTTP | http://<backend-lb-ip>:80/todolist/${request.path[id]} |

### 7.2 Configurar CORS
En cada ruta, configurar CORS:
- Allowed Origins: `*`
- Allowed Methods: GET, POST, PUT, DELETE, OPTIONS
- Allowed Headers: Content-Type, Authorization
- Exposed Headers: location
- Max Age: 3600

### 7.3 Obtener URL del API Gateway
La URL tendra el formato:
```
https://<gateway-id>.apigateway.<region>.oci.customer-oci.com
```

---

## Fase 8: Verificacion Final

### 8.1 Tests de conectividad
```bash
# Probar API Gateway - Listar todos
curl -X GET https://<api-gateway-url>/todolist

# Probar crear un todo
curl -X POST https://<api-gateway-url>/todolist \
  -H "Content-Type: application/json" \
  -d '{"description": "Test desde curl"}'

# Probar frontend (obtener IP del LoadBalancer)
kubectl get svc frontend-service -n mtdrworkshop
curl http://<frontend-lb-ip>
```

### 8.2 Checklist de verificacion
- [ ] Pods del backend running (2 replicas)
- [ ] Pods del frontend running (2 replicas)
- [ ] Conexion backend -> ATP funcionando
- [ ] API Gateway respondiendo
- [ ] Frontend cargando correctamente
- [ ] CRUD de tareas funcionando (crear, listar, actualizar, eliminar)

---

## Comandos Utiles

### Kubectl
```bash
# Ver pods
kubectl get pods -n mtdrworkshop

# Ver logs
kubectl logs -f <pod-name> -n mtdrworkshop

# Ejecutar shell en pod
kubectl exec -it <pod-name> -n mtdrworkshop -- /bin/sh

# Reiniciar deployment
kubectl rollout restart deployment/<deployment-name> -n mtdrworkshop

# Escalar replicas
kubectl scale deployment/<deployment-name> --replicas=3 -n mtdrworkshop
```

### Docker
```bash
# Listar imagenes
docker images | grep mtdr

# Eliminar imagenes antiguas
docker image prune -a
```

### OCI CLI
```bash
# Listar clusters OKE
oci ce cluster list --compartment-id <COMPARTMENT_OCID>

# Ver detalles de ATP
oci db autonomous-database get --autonomous-database-id <ATP_OCID>
```

---

## Troubleshooting

### Pod no inicia
```bash
kubectl describe pod <pod-name> -n mtdrworkshop
kubectl logs <pod-name> -n mtdrworkshop --previous
```

### Error de conexion a BD
1. Verificar secret del wallet
2. Verificar TNS_ADMIN path en deployment
3. Verificar usuario y password

### API Gateway no responde
1. Verificar security lists de VCN
2. Verificar que el backend service tenga IP externa
3. Verificar CORS configurado

### Frontend no conecta al backend
1. Verificar REACT_APP_API_URL en build
2. Verificar CORS en API Gateway
3. Verificar network policies en K8s

---

## Arquitectura Final

```
                    Internet
                        |
                        v
        +----------------------------------+
        |          API Gateway             |
        |   (Endpoint Publico HTTPS)       |
        +----------------+-----------------+
                         |
        +----------------+------------------+
        |            OKE Cluster            |
        |   +----------+    +----------+    |
        |   | Frontend |    | Backend  |    |
        |   |  Nginx   |--->| Helidon  |    |
        |   | 2 Pods   |    | 2 Pods   |    |
        |   +----------+    +----+-----+    |
        +------------------------|----------+
                                 |
                    +------------v-----------+
                    |  Autonomous Database   |
                    |        (ATP)           |
                    +------------------------+
```

---

## Proximos Pasos Opcionales

1. **CI/CD**: Configurar OCI DevOps pipelines
2. **Monitoring**: Habilitar OCI Monitoring y Logging
3. **SSL**: Configurar certificados en API Gateway
4. **DNS**: Configurar dominio personalizado
5. **WAF**: Habilitar Web Application Firewall
6. **Autoscaling**: Configurar HPA en Kubernetes
