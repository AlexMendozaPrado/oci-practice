# Guia de Configuracion - MyToDo App en OCI

Esta guia te permite desplegar la aplicacion MyToDo (React + Java Helidon + Oracle Autonomous DB) en tu propia cuenta de Oracle Cloud Infrastructure usando una instancia Compute con Docker.

## Arquitectura

```
Usuario (navegador)
    |
    v
[Frontend - Nginx :80]  -->  [Backend - Helidon :8080]  -->  [Autonomous DB]
         \__________________________|
          Compute Instance (OCI)
```

## Prerequisitos

- Cuenta de OCI (Free Tier es suficiente)
- OCI CLI instalado y configurado
- Terraform instalado (v1.0+)
- Docker instalado localmente (opcional, se puede construir en la instancia)
- Git
- Python 3.x con `oci` SDK (`pip install oci-cli`)
- SSH client

---

## Paso 1: Configurar OCI CLI

### 1.1 Instalar OCI CLI

```bash
# Windows (PowerShell)
Set-ExecutionPolicy RemoteSigned
Invoke-WebRequest https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.ps1 -OutFile install.ps1
./install.ps1

# Linux/Mac
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```

### 1.2 Configurar credenciales

```bash
oci setup config
```

Necesitaras:
- **Tenancy OCID**: OCI Console > Profile > Tenancy > OCID
- **User OCID**: OCI Console > Profile > My Profile > OCID
- **Region**: Ej. `us-ashburn-1`, `eu-frankfurt-1`
- **API Key**: El setup genera un par de llaves automaticamente

Sube la llave publica generada en OCI Console > Profile > API Keys > Add API Key.

### 1.3 Verificar configuracion

```bash
oci iam user get --user-id <TU_USER_OCID>
```

---

## Paso 2: Configurar Terraform

### 2.1 Generar SSH key para la instancia Compute

```bash
ssh-keygen -t rsa -b 2048 -f ~/.ssh/oci_compute_key -N ""
```

### 2.2 Crear archivo terraform.tfvars

Crea el archivo `mtdrworkshop/terraform/terraform.tfvars` con tus valores:

```hcl
ociTenancyOcid      = "ocid1.tenancy.oc1..aaaa..."      # Tu Tenancy OCID
ociUserOcid         = "ocid1.user.oc1..aaaa..."          # Tu User OCID
ociCompartmentOcid  = "ocid1.compartment.oc1..aaaa..."   # Tu Compartment OCID (puede ser el Tenancy para root)
ociRegionIdentifier = "us-ashburn-1"                      # Tu region
mtdrDbName          = "tododb"
runName             = "mtdr"
ssh_public_key      = "ssh-rsa AAAA... tu@maquina"       # Contenido de ~/.ssh/oci_compute_key.pub
```

> **Nota**: Este archivo esta en `.gitignore` y nunca debe commitearse.

### 2.3 Inicializar y aplicar Terraform

```bash
cd mtdrworkshop/terraform
terraform init
terraform plan
terraform apply
```

Esto crea:
- VCN con subnets
- Autonomous Database (Free Tier)
- API Gateway
- Compute Instance con Docker preinstalado
- Security lists (puertos 22, 80, 8080)

### 2.4 Anotar los outputs

Al finalizar, Terraform imprime valores importantes:

```
app_instance_public_ip = "X.X.X.X"        # IP publica de tu instancia
app_instance_id = "ocid1.instance..."
autonomous_database_admin_password = ["..."]  # Password de ADMIN del DB
```

Guarda estos valores, los necesitaras en los siguientes pasos.

---

## Paso 3: Configurar la Base de Datos

### 3.1 Descargar el Wallet

```python
# Ejecutar con: python download_wallet.py
import oci

config = oci.config.from_file()
db_client = oci.database.DatabaseClient(config)

# Obtener el OCID del DB (listar databases en tu compartment)
compartment_id = config['tenancy']  # o tu compartment OCID
dbs = db_client.list_autonomous_databases(compartment_id=compartment_id).data

for db in dbs:
    if db.db_name.lower() == 'tododb':
        db_ocid = db.id
        print(f"DB encontrada: {db.display_name} ({db_ocid})")
        break

wallet = db_client.generate_autonomous_database_wallet(
    autonomous_database_id=db_ocid,
    generate_autonomous_database_wallet_details=oci.database.models.GenerateAutonomousDatabaseWalletDetails(
        password='WalletPassword123!'
    )
)

with open('mtdrworkshop/wallet.zip', 'wb') as f:
    for chunk in wallet.data.raw.stream(1024 * 1024):
        f.write(chunk)

print('Wallet descargado en mtdrworkshop/wallet.zip')
```

Extraer el wallet:

```bash
mkdir -p mtdrworkshop/wallet
cd mtdrworkshop/wallet
unzip ../wallet.zip
```

### 3.2 Crear usuario y tabla

Instalar el driver Python de Oracle:

```bash
pip install oracledb
```

Ejecutar el setup (reemplaza `<DB_ADMIN_PASSWORD>` con el password del output de Terraform):

```python
# Ejecutar con: python setup_db.py
import oracledb

wallet_dir = 'mtdrworkshop/wallet'

connection = oracledb.connect(
    user='ADMIN',
    password='<DB_ADMIN_PASSWORD>',   # Del output de terraform
    dsn='tododb_tp',
    config_dir=wallet_dir,
    wallet_location=wallet_dir,
    wallet_password='WalletPassword123!'
)
print('Conectado como ADMIN')
cursor = connection.cursor()

# Crear TODOUSER (password sin contener "todo" ni "user")
cursor.execute('CREATE USER TODOUSER IDENTIFIED BY "MyApp2024Secure#x"')
print('TODOUSER creado')

for g in ['GRANT CONNECT TO TODOUSER',
          'GRANT RESOURCE TO TODOUSER',
          'ALTER USER TODOUSER QUOTA UNLIMITED ON DATA',
          'GRANT CREATE SESSION TO TODOUSER']:
    cursor.execute(g)
    print(f'OK: {g}')
connection.close()

# Crear tabla como TODOUSER
conn2 = oracledb.connect(
    user='TODOUSER',
    password='MyApp2024Secure#x',
    dsn='tododb_tp',
    config_dir=wallet_dir,
    wallet_location=wallet_dir,
    wallet_password='WalletPassword123!'
)
cursor2 = conn2.cursor()
cursor2.execute('''
    CREATE TABLE todoitem (
        id NUMBER GENERATED ALWAYS AS IDENTITY,
        description VARCHAR2(32000),
        creation_ts TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        done NUMBER(1,0),
        PRIMARY KEY (id)
    )
''')
conn2.commit()
conn2.close()
print('Tabla todoitem creada')
```

---

## Paso 4: Construir y desplegar los contenedores

### 4.1 Conectarse a la instancia

```bash
ssh -i ~/.ssh/oci_compute_key opc@<INSTANCE_PUBLIC_IP>
```

> La primera conexion puede tardar unos minutos despues de crear la instancia, mientras cloud-init instala Docker. Verificar con: `sudo cloud-init status`

### 4.2 Subir archivos a la instancia

Desde tu maquina local:

```bash
# Crear directorios
ssh -i ~/.ssh/oci_compute_key opc@<IP> "mkdir -p /home/opc/mtdr/backend /home/opc/mtdr/frontend /home/opc/mtdr/wallet"

# Subir wallet
scp -i ~/.ssh/oci_compute_key -r mtdrworkshop/wallet/* opc@<IP>:/home/opc/mtdr/wallet/

# Subir backend
scp -i ~/.ssh/oci_compute_key mtdrworkshop/backend/pom.xml opc@<IP>:/home/opc/mtdr/backend/
scp -i ~/.ssh/oci_compute_key -r mtdrworkshop/backend/src opc@<IP>:/home/opc/mtdr/backend/

# Subir frontend
scp -i ~/.ssh/oci_compute_key mtdrworkshop/frontend/package.json mtdrworkshop/frontend/Dockerfile mtdrworkshop/frontend/nginx.conf opc@<IP>:/home/opc/mtdr/frontend/
scp -i ~/.ssh/oci_compute_key -r mtdrworkshop/frontend/src mtdrworkshop/frontend/public opc@<IP>:/home/opc/mtdr/frontend/
```

### 4.3 Configurar sqlnet.ora del wallet

En la instancia, actualizar la ruta del wallet para que apunte al path dentro del contenedor:

```bash
ssh -i ~/.ssh/oci_compute_key opc@<IP>

cat > /home/opc/mtdr/wallet/sqlnet.ora << 'EOF'
WALLET_LOCATION = (SOURCE = (METHOD = file) (METHOD_DATA = (DIRECTORY="/mtdrworkshop/creds")))
SSL_SERVER_DN_MATCH=yes
EOF
```

### 4.4 Construir imagenes Docker en la instancia

```bash
# Backend
cd /home/opc/mtdr/backend
docker build -t todolistapp-backend:1.0 -f src/main/docker/Dockerfile .

# Frontend (reemplazar <IP> con la IP publica de tu instancia)
cd /home/opc/mtdr/frontend
docker build --build-arg REACT_APP_API_URL=http://<INSTANCE_PUBLIC_IP>:8080/todolist \
  -t todolistapp-frontend:1.0 .
```

### 4.5 Ejecutar los contenedores

```bash
# Backend
docker run -d --name backend \
  -p 8080:8080 \
  -v /home/opc/mtdr/wallet:/mtdrworkshop/creds \
  -e "database.user=TODOUSER" \
  -e "database.url=jdbc:oracle:thin:@tododb_tp?TNS_ADMIN=/mtdrworkshop/creds" \
  -e "todo.table.name=todoitem" \
  -e "dbpassword=MyApp2024Secure#x" \
  -e "OCI_REGION=us-ashburn-1" \
  todolistapp-backend:1.0

# Frontend
docker run -d --name frontend \
  -p 80:80 \
  todolistapp-frontend:1.0
```

---

## Paso 5: Verificar el despliegue

### 5.1 Verificar contenedores

```bash
docker ps
docker logs backend | head -10
# Debe mostrar: "webserver is up! http://localhost:8080/todolist"
```

### 5.2 Probar el API

```bash
# Listar todos (debe retornar [])
curl http://localhost:8080/todolist

# Crear un item
curl -X POST http://localhost:8080/todolist \
  -H "Content-Type: application/json" \
  -d '{"description":"Mi primer TODO","done":false}'

# Listar de nuevo (debe retornar el item creado)
curl http://localhost:8080/todolist
```

> **Nota**: La primera operacion POST puede tardar ~15-30 segundos mientras el pool de conexiones de Oracle se inicializa. Las siguientes son rapidas.

### 5.3 Abrir en navegador

Visita `http://<INSTANCE_PUBLIC_IP>` en tu navegador para ver la aplicacion React.

---

## Notas importantes

### Seguridad

- **No expongas el puerto 8080 directamente en produccion**. Usa un API Gateway o reverse proxy con HTTPS.
- Las security lists actuales permiten trafico desde `0.0.0.0/0`. En produccion, restringe los origenes.
- Cambia el password del TODOUSER (`MyApp2024Secure#x`) por uno propio.
- El wallet del DB nunca debe committearse al repositorio (esta en `.gitignore`).

### Troubleshooting

| Problema | Solucion |
|----------|----------|
| `docker: command not found` | cloud-init aun no termino. Esperar y verificar: `sudo cloud-init status` |
| Backend no inicia | Verificar logs: `docker logs backend` |
| ORA-01017 invalid password | Verificar el password en `terraform output -json autonomous_database_admin_password` |
| POST cuelga la primera vez | Comportamiento normal - el pool de conexiones tarda en inicializarse. Esperar ~30s |
| Frontend no carga datos | Verificar que `REACT_APP_API_URL` apunta a la IP correcta |
| No se puede conectar por SSH | Verificar security list, firewall, y que la key sea la correcta |

### Limpieza de recursos

Para destruir todos los recursos y evitar costos:

```bash
cd mtdrworkshop/terraform
terraform destroy
```

### Estructura de archivos clave

```
mtdrworkshop/
  backend/
    pom.xml                          # Dependencias Maven (Helidon SE 2.4.2)
    src/main/docker/Dockerfile       # Multi-stage build: Maven + Eclipse Temurin 11
    src/main/java/.../Main.java      # Punto de entrada
    src/main/java/.../TodoItemStorage.java  # Acceso a DB (UCP pool)
    src/main/resources/application.yaml     # Config del server (port 8080)
  frontend/
    Dockerfile                       # Multi-stage build: Node 18 + Nginx
    nginx.conf                       # Configuracion de Nginx
    src/API.js                       # URL del backend (configurar antes de build)
    package.json                     # Dependencias React 17
  terraform/
    main.tf                          # Provider OCI
    main-var.tf                      # Variables (incluye ssh_public_key)
    core.tf                          # VCN, subnets, gateways
    compute.tf                       # Instancia Compute + security list
    atp.tf                           # Autonomous Database
    apigw.tf                         # API Gateway
    terraform.tfvars                 # TUS valores (no commitear)
```
