# Guia de Configuracion Inicial de OCI

Esta guia te llevara paso a paso para configurar Oracle Cloud Infrastructure antes de desplegar la aplicacion.

---

## Paso 1: Crear Cuenta de OCI (Free Tier)

1. Ir a: https://www.oracle.com/cloud/free/
2. Click en "Start for free"
3. Completar el registro:
   - Email valido
   - Pais y nombre
   - Verificacion de telefono
   - **Tarjeta de credito** (no se cobra, solo verificacion)
4. Seleccionar **Home Region** (no se puede cambiar despues):
   - Recomendado: La mas cercana a tu ubicacion
   - Ejemplos: `Brazil East (Sao Paulo)`, `US East (Ashburn)`

5. Esperar activacion (puede tomar unos minutos)

**Free Tier incluye:**
- 2 AMD VMs (1/8 OCPU, 1GB RAM cada una)
- 4 ARM VMs (24GB RAM total)
- 2 Autonomous Databases (20GB cada una)
- Object Storage (20GB)
- Valido para siempre (Always Free)

---

## Paso 2: Obtener OCIDs necesarios

### 2.1 Tenancy OCID
1. Ir a OCI Console: https://cloud.oracle.com
2. Click en icono de **Profile** (esquina superior derecha)
3. Click en **Tenancy: [nombre]**
4. Copiar el **OCID** (formato: `ocid1.tenancy.oc1..xxxx`)

### 2.2 User OCID
1. Click en icono de **Profile**
2. Click en **My Profile**
3. Copiar el **OCID** (formato: `ocid1.user.oc1..xxxx`)

### 2.3 Compartment OCID
1. Menu hamburguesa (≡) → Identity & Security → Compartments
2. Puedes usar el **root compartment** o crear uno nuevo:
   - Click "Create Compartment"
   - Name: `oci-practice`
   - Description: `Compartment para practica OCI`
3. Copiar el **OCID** del compartment

### 2.4 Region Identifier
1. Ver en la barra superior de la consola
2. O en: Menu → Administration → Tenancy Details → Home Region

**Ejemplos de Region Identifier:**
| Region | Identifier |
|--------|------------|
| Brazil East (Sao Paulo) | `sa-saopaulo-1` |
| US East (Ashburn) | `us-ashburn-1` |
| US West (Phoenix) | `us-phoenix-1` |
| Germany (Frankfurt) | `eu-frankfurt-1` |

---

## Paso 3: Instalar OCI CLI

### Windows (PowerShell como Admin)
```powershell
Set-ExecutionPolicy RemoteSigned
Invoke-WebRequest https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.ps1 -OutFile install.ps1
.\install.ps1 -AcceptAllDefaults
```

### macOS / Linux
```bash
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```

### Verificar instalacion
```bash
oci --version
# Debe mostrar algo como: 3.x.x
```

---

## Paso 4: Configurar OCI CLI

### 4.1 Ejecutar configuracion
```bash
oci setup config
```

### 4.2 Responder las preguntas:

```
Enter a location for your config [~/.oci/config]: (Enter - usar default)

Enter a user OCID: ocid1.user.oc1..xxxx (pegar tu User OCID)

Enter a tenancy OCID: ocid1.tenancy.oc1..xxxx (pegar tu Tenancy OCID)

Enter a region: sa-saopaulo-1 (tu region)

Do you want to generate a new API Signing RSA key pair? [Y/n]: Y

Enter a directory for your keys [~/.oci]: (Enter - usar default)

Enter a name for your key [oci_api_key]: (Enter - usar default)

Enter a passphrase (empty for no passphrase): (Enter - sin passphrase)
```

### 4.3 Subir API Key a OCI
El comando anterior genero una **public key**. Debes subirla a OCI:

1. El comando te mostrara la ubicacion del archivo `.pem`
2. Ir a OCI Console → Profile → My Profile → API Keys
3. Click "Add API Key"
4. Seleccionar "Paste Public Key"
5. Abrir el archivo `~/.oci/oci_api_key_public.pem` y pegar contenido
6. Click "Add"

### 4.4 Verificar configuracion
```bash
oci iam region list --output table
```

Debe mostrar lista de regiones. Si hay error, revisar:
- API Key subida correctamente
- OCIDs correctos en `~/.oci/config`

---

## Paso 5: Crear Auth Token (para Docker/OCIR)

1. OCI Console → Profile → My Profile
2. Ir a seccion **Auth Tokens** (menu izquierdo)
3. Click "Generate Token"
4. Description: `docker-token`
5. Click "Generate Token"
6. **IMPORTANTE: Copiar y guardar el token** (solo se muestra una vez)

Este token se usa como password para `docker login`.

---

## Paso 6: Verificar Todo

### Test OCI CLI
```bash
# Listar compartments
oci iam compartment list --output table

# Listar availability domains
oci iam availability-domain list --output table
```

### Guardar tus credenciales
Crea un archivo local (NO commitear) con tus datos:

```bash
# Archivo: mis-credenciales-oci.txt (agregar a .gitignore)

TENANCY_OCID=ocid1.tenancy.oc1..xxxx
USER_OCID=ocid1.user.oc1..xxxx
COMPARTMENT_OCID=ocid1.compartment.oc1..xxxx
REGION=sa-saopaulo-1
AUTH_TOKEN=tu-auth-token-aqui
```

---

## Paso 7: Instalar Herramientas Adicionales

### Docker Desktop
- Windows/Mac: https://www.docker.com/products/docker-desktop
- Verificar: `docker --version`

### kubectl
```bash
# Windows (con chocolatey)
choco install kubernetes-cli

# macOS
brew install kubectl

# Verificar
kubectl version --client
```

### Terraform (opcional - para crear infraestructura)
```bash
# Windows (con chocolatey)
choco install terraform

# macOS
brew install terraform

# Verificar
terraform --version
```

### Java 11 y Maven (para compilar backend)
```bash
# Verificar Java
java -version  # Debe ser 11+

# Verificar Maven
mvn --version  # Debe ser 3.x
```

---

## Checklist Final

Antes de continuar con el despliegue, verifica:

- [ ] Cuenta OCI activa
- [ ] Tenancy OCID guardado
- [ ] User OCID guardado
- [ ] Compartment OCID guardado
- [ ] Region identificada
- [ ] OCI CLI instalado y funcionando
- [ ] API Key configurada y subida
- [ ] Auth Token generado y guardado
- [ ] Docker instalado
- [ ] kubectl instalado

---

## Problemas Comunes

### Error: "NotAuthenticated"
- Verificar que la API Key este subida en OCI Console
- Verificar que los OCIDs en `~/.oci/config` sean correctos

### Error: "Authorization failed"
- El usuario no tiene permisos suficientes
- Si es cuenta nueva, deberia tener permisos de admin

### OCI CLI no reconocido
- Reiniciar terminal despues de instalar
- Verificar que este en el PATH

### Docker login falla
- Username: `<namespace>/<username>` (namespace es del tenancy)
- Password: Auth Token (no la password de OCI)

---

## Siguiente Paso

Una vez completada esta configuracion, ejecuta en Claude Code:

```
Continuar con Fase 1: Crear Dockerfiles
```

Y proporciona los siguientes datos:
- Tu Region (ej: sa-saopaulo-1)
- Tu Compartment OCID
