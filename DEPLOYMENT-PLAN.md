# Plan de Deployment - MyToDo App en OCI (sin Kubernetes)

## Estado actual de la infraestructura

| Recurso | Estado | Detalles |
|---------|--------|----------|
| VCN | ACTIVE | 10.0.0.0/16, nombre: mtdrworkshop |
| Subnets | ACTIVE | endpoint (10.0.0.0/28), nodepool (10.0.10.0/24), svclb (10.0.20.0/24) |
| Internet Gateway | ACTIVE | Para subnets publicas |
| NAT Gateway | ACTIVE | Para subnet privada |
| Service Gateway | ACTIVE | Acceso a OCI services |
| Autonomous DB | ACTIVE | MTDRDB, Free Tier, password: generado por Terraform |
| API Gateway | ACTIVE | Subnet svclb, tipo PUBLIC |
| OKE Cluster | ACTIVE | v1.33.1 (auth bloqueada - 401) |
| Node Pool | FAILED | No se creo correctamente |
| OCIR Namespace | -- | idzdvdyc2vti |

## Problema pendiente

kubectl retorna 401 Unauthorized. El endpoint `/cluster_request` del servicio OKE rechaza tokens validos. Investigacion completa realizada - posible issue del servicio o Identity Domain.

## Plan de Deployment con Compute (sin K8s)

### Paso 1: Crear instancia Compute via Terraform

Agregar a `mtdrworkshop/terraform/compute.tf`:

```hcl
# Security list para la instancia Compute
resource "oci_core_security_list" "compute_security_list" {
  compartment_id = var.ociCompartmentOcid
  vcn_id         = oci_core_vcn.okevcn.id
  display_name   = "Compute Security List"

  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options { min = 22; max = 22 }
  }
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options { min = 80; max = 80 }
  }
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options { min = 8080; max = 8080 }
  }
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# Subnet para Compute
resource "oci_core_subnet" "compute_subnet" {
  cidr_block     = "10.0.30.0/24"
  compartment_id = var.ociCompartmentOcid
  vcn_id         = oci_core_vcn.okevcn.id
  display_name   = "ComputeSubnet"
  dns_label      = "compute"
  security_list_ids = [oci_core_security_list.compute_security_list.id]
  route_table_id    = oci_core_vcn.okevcn.default_route_table_id
}

# Compute instance
resource "oci_core_instance" "app_instance" {
  availability_domain = data.oci_identity_availability_domain.ad1.name
  compartment_id      = var.ociCompartmentOcid
  display_name        = "mtdr-app-server"
  shape               = "VM.Standard.E2.1"

  source_details {
    source_type = "image"
    source_id   = local.oracle_linux_images.0
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.compute_subnet.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(<<-EOF
      #!/bin/bash
      yum install -y docker
      systemctl enable docker
      systemctl start docker
      usermod -aG docker opc
      # Install docker-compose
      curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
      chmod +x /usr/local/bin/docker-compose
      # Open firewall ports
      firewall-cmd --permanent --add-port=80/tcp
      firewall-cmd --permanent --add-port=8080/tcp
      firewall-cmd --reload
    EOF
    )
  }
}

output "app_instance_public_ip" {
  value = oci_core_instance.app_instance.public_ip
}
```

Agregar variable SSH en `main-var.tf`:
```hcl
variable "ssh_public_key" {
  description = "SSH public key for compute instance access"
  type        = string
}
```

Prerequisito: Generar SSH key si no existe:
```powershell
ssh-keygen -t rsa -b 2048 -f $HOME\.ssh\oci_compute_key -N ""
```

Agregar al `terraform.tfvars`:
```
ssh_public_key = "<contenido de oci_compute_key.pub>"
```

Ejecutar:
```powershell
cd mtdrworkshop\terraform
terraform plan
terraform apply
```

### Paso 2: Build y push Docker images a OCIR

Prerequisito: Login al registro OCIR:
```powershell
# Crear Auth Token en OCI Console: Identity > Users > Auth Tokens
docker login iad.ocir.io -u idzdvdyc2vti/fluidlizard97@hotmail.com
# Password: el auth token generado
```

Build backend:
```powershell
cd mtdrworkshop\backend
docker build -t iad.ocir.io/idzdvdyc2vti/mtdr/todolistapp-backend:1.0 -f src\main\docker\Dockerfile .
docker push iad.ocir.io/idzdvdyc2vti/mtdr/todolistapp-backend:1.0
```

Build frontend (actualizar API_URL primero en frontend/src/API.js):
```powershell
cd mtdrworkshop\frontend
# Editar src/API.js con la URL del API Gateway
docker build --build-arg REACT_APP_API_URL=https://<api-gateway-url>/todolist -t iad.ocir.io/idzdvdyc2vti/mtdr/todolistapp-frontend:1.0 .
docker push iad.ocir.io/idzdvdyc2vti/mtdr/todolistapp-frontend:1.0
```

### Paso 3: Configurar Base de Datos

Descargar wallet:
```python
# Usando OCI SDK (Python)
import oci
config = oci.config.from_file()
db_client = oci.database.DatabaseClient(config)
# Obtener OCID del autonomous database desde terraform output
wallet = db_client.generate_autonomous_database_wallet(
    autonomous_database_id="<DB_OCID>",
    generate_autonomous_database_wallet_details=oci.database.models.GenerateAutonomousDatabaseWalletDetails(
        password="WalletPassword123!"
    )
)
with open("wallet.zip", "wb") as f:
    for chunk in wallet.data.raw.stream(1024):
        f.write(chunk)
```

Crear usuario y tabla:
```sql
-- Conectar como ADMIN
CREATE USER TODOUSER IDENTIFIED BY "<password>";
GRANT CONNECT, RESOURCE TO TODOUSER;
ALTER USER TODOUSER QUOTA UNLIMITED ON DATA;

-- Conectar como TODOUSER
CREATE TABLE todoitem (
  id NUMBER GENERATED ALWAYS AS IDENTITY,
  description VARCHAR2(32000),
  creation_ts TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  done NUMBER(1,0),
  PRIMARY KEY (id)
);
```

### Paso 4: Deploy containers en Compute

SSH a la instancia:
```powershell
ssh -i $HOME\.ssh\oci_compute_key opc@<INSTANCE_PUBLIC_IP>
```

En la instancia:
```bash
# Login a OCIR
docker login iad.ocir.io -u idzdvdyc2vti/fluidlizard97@hotmail.com

# Crear directorio para wallet
mkdir -p /home/opc/wallet
# (copiar wallet.zip y extraer aqui)

# Run backend
docker run -d --name backend \
  -p 8080:8080 \
  -v /home/opc/wallet:/mtdrworkshop/creds \
  -e "database.user=TODOUSER" \
  -e "database.url=jdbc:oracle:thin:@mtdrdb_tp?TNS_ADMIN=/mtdrworkshop/creds" \
  -e "todo.table.name=todoitem" \
  -e "dbpassword=<TODOUSER_PASSWORD>" \
  iad.ocir.io/idzdvdyc2vti/mtdr/todolistapp-backend:1.0

# Run frontend
docker run -d --name frontend \
  -p 80:80 \
  iad.ocir.io/idzdvdyc2vti/mtdr/todolistapp-frontend:1.0
```

### Paso 5: Configurar API Gateway

Crear deployment en API Gateway via OCI CLI o Console:
```python
# Usando OCI SDK
import oci
config = oci.config.from_file()
apigw_client = oci.apigateway.DeploymentClient(config)

deployment = apigw_client.create_deployment(
    create_deployment_details=oci.apigateway.models.CreateDeploymentDetails(
        display_name="todolist-deployment",
        gateway_id="<API_GATEWAY_OCID>",
        compartment_id="<COMPARTMENT_OCID>",
        path_prefix="/",
        specification=oci.apigateway.models.ApiSpecification(
            routes=[
                oci.apigateway.models.ApiSpecificationRoute(
                    path="/todolist",
                    methods=["GET", "POST"],
                    backend=oci.apigateway.models.HTTPBackend(
                        type="HTTP_BACKEND",
                        url="http://<INSTANCE_IP>:8080/todolist"
                    )
                ),
                oci.apigateway.models.ApiSpecificationRoute(
                    path="/todolist/{id}",
                    methods=["GET", "PUT", "DELETE"],
                    backend=oci.apigateway.models.HTTPBackend(
                        type="HTTP_BACKEND",
                        url="http://<INSTANCE_IP>:8080/todolist/${request.path[id]}"
                    )
                )
            ]
        )
    )
)
```

### Paso 6: Verificacion final

1. Abrir en navegador: `http://<INSTANCE_PUBLIC_IP>` (frontend directo)
2. O via API Gateway: `https://<API_GATEWAY_URL>/`
3. Crear un TODO item
4. Verificar que aparece en la lista
5. Marcar como completado
6. Eliminar

## Valores de referencia

- Region: us-ashburn-1
- Tenancy OCID: ocid1.tenancy.oc1..aaaaaaaa6yu6oae63jav5lcz7ve3ouzhpwkkjmfgldkc3vpkvygfoo4fvhha
- User OCID: ocid1.user.oc1..aaaaaaaayizugg5dusl5lp4shnvqhkflm6qyquj45m56twv27zt6tsffbdhq
- Cluster OCID: ocid1.cluster.oc1.iad.aaaaaaaalgra5pnda6dtszp2s2wdzpqqcyfciwzdmtinfncnzc2zipgreoiq
- OCIR Namespace: idzdvdyc2vti
- DB Name: mtdrdb
- DB Password: Generado por Terraform (ver terraform.tfstate)
- API Key Fingerprint: 86:48:b0:eb:0f:d2:ab:bd:9b:88:aa:18:42:71:2e:32

## Migracion futura a Kubernetes

Cuando se resuelva el problema de autenticacion OKE (401):
1. Crear K8s secrets para DB wallet y password
2. Aplicar los deployments YAML existentes en backend/src/main/k8s/ y frontend/k8s/
3. Configurar API Gateway para apuntar a los K8s services
4. Eliminar la instancia Compute
