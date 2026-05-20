# AWS Landing Zone — Terraform

![Terraform](https://img.shields.io/badge/Terraform_1.15-7B42BC?style=flat&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-232F3E?style=flat&logo=amazonwebservices&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat&logo=githubactions&logoColor=white)

Implementación de una AWS Landing Zone multicuenta con Terraform. Arquitectura hub-spoke diseñada para entornos productivos con segmentación por función, networking centralizado y despliegue automatizado vía CI/CD con OIDC y cross-account role assumption.

---

## Arquitectura

![Diagrama de Arquitectura](diagrams/arquitectura.png)

### Cuentas y Organizational Units

| Cuenta | OU | Propósito |
|--------|-----|-----------|
| **Root** | — | AWS Organizations, Identity Center (SSO), Cost Explorer |
| **Tooling** | Share Resources | Remote state de Terraform (S3 con versionado, cifrado y locking nativo), rol OIDC base |
| **Connectivity** | Share Resources | Networking centralizado: VPC hub (Ingress/Egress), Transit Gateway, Internet Gateway |
| **Workloads** | Workloads | Cargas de trabajo multi-entorno (dev/prod via Terraform workspaces) |

### Networking — Hub-Spoke

Modelo hub-spoke donde la cuenta **Connectivity** gestiona el networking centralizado y **Workloads** consume la conectividad via Transit Gateway.

**Hub — Connectivity Account** (desplegado en `us-east-1a`, `us-east-1b`):

- **VPC IngresEgress**: subnets públicas con Internet Gateway, subnets privadas TGW para los ENIs del Transit Gateway.
- **Transit Gateway**: punto central de la topología hub-spoke. Los spokes se conectan via attachments.
- **Internet Gateway**: salida directa a internet para las subnets públicas del hub.
- **NAT Gateway**: salida a internet para tráfico proveniente de los spokes (TGW subnets → NAT → Internet).

**Routing del Hub**:

| Route Table | Destino | Siguiente salto |
|-------------|---------|-----------------|
| Public subnets | `0.0.0.0/0` | Internet Gateway |
| Public subnets | CIDRs de cada spoke | Transit Gateway |
| TGW subnets | `0.0.0.0/0` | NAT Gateway |

Las rutas hacia los spokes se generan dinámicamente a partir de `var.spoke_cidrs` (`flatten` + `for_each`). Si un spoke no existe en la variable, su ruta no se crea.

**Spokes — Workloads Account** (un spoke por workspace):

- Las subnets, CIDRs y estructura de cada spoke son definidos por el usuario via variables — la cantidad y tipo de subnets dependen del caso de uso.
- Cada spoke se attache al Transit Gateway del hub via `terraform_remote_state`.
- Convención de naming para subnets: `{tipo}-{sufijo}` (ej: `app-a`, `db-b`, `tgw-a`). El prefijo antes del primer guión determina el tipo y agrupa subnets en la misma route table.

**Routing de los Spokes**:

| Route Table | Destino | Siguiente salto |
|-------------|---------|-----------------|
| App/DB subnets | `0.0.0.0/0` | Transit Gateway |
| TGW subnets | — | Sin ruta default (subnets de attachment, evita loop circular) |

**Flujo de tráfico spoke → internet**: Spoke (app/db subnet) → TGW → Hub (TGW subnet) → NAT Gateway → Internet Gateway → Internet.

### Compute y Aplicación (Workloads Account)

```
Internet → CloudFront (CDN) → S3 (estáticos)
Internet → API Gateway → ALB → Auto Scaling Group (EC2) → RDS / DocumentDB
```

### CI/CD — Cross-Account OIDC

```
GitHub Actions → OIDC → Rol base (Tooling) → AssumeRole → Rol destino (Connectivity/Workloads)
```

Pipeline con `workflow_dispatch`:
- Selección de cuenta (`connectivity` | `workloads`)
- Selección de acción (`plan` | `apply` | `destroy` | `unlock`)
- Selección de entorno (`dev` | `prod`) para workloads
- Resolución automática del rol de despliegue y variables de red por cuenta/entorno via `GITHUB_ENV`

**Secrets requeridos**:

| Secret | Propósito |
|--------|-----------|
| `AWS_ROLE_ARN` | Rol OIDC base en la cuenta Tooling |
| `ROLE_ARN_CONNECTIVITY` | Rol de despliegue en Connectivity |
| `ROLE_ARN_WORKLOADS_DEV` | Rol de despliegue en Workloads (dev) |
| `ROLE_ARN_WORKLOADS_PROD` | Rol de despliegue en Workloads (prod) |
| `S3_STATE` | Nombre del bucket S3 para remote state |

**Variables de repositorio** (GitHub Settings → Variables):

| Variable | Formato | Propósito |
|----------|---------|-----------|
| `IN_OUT_CIDR` | JSON `object` | VPC del hub: CIDR + subnets (pasado como `TF_VAR_cidr_ingress_egress`) |
| `SPOKE_CIDRS` | JSON `map(object)` | Configuración de red completa de cada spoke por workspace (pasado como `TF_VAR_cidrs_spokes`) |
| `VPCS` | JSON `map(string)` | CIDRs de los spokes para ruteo en el hub (pasado como `TF_VAR_spoke_cidrs`) |

Las variables de red no tienen valores default en Terraform — los valores se gestionan exclusivamente desde GitHub para mantener una fuente de verdad única. El pipeline inyecta condicionalmente las variables según la cuenta seleccionada (connectivity recibe `IN_OUT_CIDR` + `VPCs`, workloads recibe `SPOKE_CIDRS`).

### State Management

```
Tooling Account → S3 Bucket (versionado + cifrado AES256 + locking nativo + public access block)
```

Script de bootstrap (`stateUtil.sh`) para crear el bucket con backend local y migrar el state a S3 automáticamente.

---

## Stack

| Capa | Herramienta |
|------|-------------|
| **IaC** | Terraform 1.15 con módulos reutilizables por dominio |
| **CI/CD** | GitHub Actions con OIDC + cross-account role assumption |
| **State** | S3 backend en cuenta Tooling (versionado + locking nativo) |
| **Entornos** | Terraform workspaces (dev/prod) en cuenta Workloads |
| **Acceso** | AWS Identity Center (SSO) para acceso por CLI |
| **Región** | `us-east-1` |

---

## Estructura de carpetas

```
.
├── .github/workflows/
│   └── deploy.yml                  # Pipeline CI/CD con OIDC + cross-account
├── diagrams/
│   ├── arquitectura.drawio         # Fuente editable del diagrama
│   └── arquitectura.png            # Diagrama exportado
├── accounts/
│   ├── tooling/
│   │   ├── provider.tf
│   │   ├── main.tf                 # S3 state bucket (versionado, cifrado, locking)
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── stateUtil.sh            # Bootstrap/destroy del state remoto
│   │   └── terraform.example.tfvars
│   ├── connectivity/
│   │   ├── provider.tf             # assume_role cross-account
│   │   ├── backend.tf
│   │   ├── main.tf                 # VPC hub + TGW + IGW + NAT GW + rutas dinámicas
│   │   ├── variables.tf            # cidr_ingress_egress + spoke_cidrs (sin defaults)
│   │   └── outputs.tf              # Exporta transit_id, attachment_ids, internet_gw, nat_gw
│   └── workloads/
│       ├── provider.tf             # assume_role cross-account, workspace tags
│       ├── backend.tf
│       ├── main.tf                 # Remote state connectivity + VPC spoke + TGW attachment + rutas
│       ├── variables.tf            # cidrs_spokes con tipo explícito (sin defaults)
│       └── outputs.tf
└── modules/
    ├── networking/
    │   ├── vpc/                    # VPC + Subnets (for_each, multi-VPC, TGW attachment output)
    │   └── transit-gateway/        # TGW VPC attachments (for_each sobre mapa de VPCs)
    ├── compute/
    │   ├── ec2/
    │   ├── asg/
    │   └── alb/
    ├── database/
    │   ├── rds/
    │   └── documentdb/
    └── storage/
        ├── s3/                     # Bucket con versionado, cifrado, public access block
        └── cdn/                    # CloudFront distribution
```

---

## Decisiones de diseño

**¿Por qué una cuenta de Connectivity separada?**  
Centralizar el networking en una cuenta dedicada permite controlar todo el tráfico de entrada/salida desde un único punto, simplifica el firewall perimetral y facilita la auditoría de flujos de red sin tocar las cuentas de aplicación.

**¿Por qué Transit Gateway en vez de VPC Peering?**  
Transit Gateway escala a N VPCs sin relaciones de peering punto a punto. Al agregar nuevas cuentas o VPCs al entorno, solo se requiere un attachment al TGW existente, sin modificar route tables en cada VPC.

**¿Por qué las variables de red viven en GitHub y no en Terraform?**  
Los defaults hardcodeados en `variables.tf` generan duplicación: los CIDRs de los spokes aparecerían tanto en workloads como en connectivity. Centralizar los valores en GitHub repo variables crea una fuente de verdad única. El pipeline inyecta condicionalmente solo las variables que cada cuenta necesita, evitando warnings por variables no declaradas.

**¿Por qué las subnets TGW no tienen ruta default al Transit Gateway?**  
Las subnets TGW son los puntos de attachment — el tráfico entra a la VPC por ellas desde el Transit Gateway. Agregar una ruta `0.0.0.0/0 → TGW` en su route table crearía un loop circular: el tráfico llegaría desde el TGW, la route table lo enviaría de vuelta al TGW, y así indefinidamente.

**¿Por qué Terraform workspaces para entornos?**  
Los workspaces permiten manejar dev y prod con la misma configuración, diferenciando solo CIDRs y tags. El workspace se selecciona en el pipeline, nunca manualmente. Evita duplicar código entre entornos.

**¿Por qué cross-account role assumption?**  
Un único rol OIDC en la cuenta Tooling asume roles de despliegue en cada cuenta destino. Cada cuenta tiene su propio rol con permisos acotados a lo que necesita. El pipeline resuelve el rol correcto automáticamente según la cuenta y el entorno seleccionados.

**¿Por qué OIDC en lugar de access keys en CI/CD?**  
Las credenciales de larga duración son el vector de compromiso más común en pipelines. OIDC emite tokens temporales con el scope mínimo necesario para cada ejecución — sin secrets que rotar ni credenciales que filtrar.

**¿Por qué S3 locking nativo en lugar de DynamoDB?**  
Terraform 1.10+ soporta locking nativo en S3 (`use_lockfile = true`), eliminando la necesidad de una tabla DynamoDB adicional. Menos infraestructura, mismo resultado.

---

## Uso

### Prerrequisitos

- Terraform >= 1.10
- AWS CLI v2 configurado con Identity Center (SSO)
- AWS Organizations habilitado con las OUs creadas
- Rol OIDC configurado para GitHub Actions
- Roles de despliegue cross-account creados en cada cuenta destino

### Bootstrap del state remoto

```bash
cd accounts/tooling
cp terraform.example.tfvars terraform.tfvars  # Editar con valores reales
./stateUtil.sh bootstrap <aws-profile>
```

Esto crea el bucket S3, migra el state de local a remoto y genera el `config.hcl` con la configuración del backend.

### Despliegue via CI/CD

Desde GitHub → Actions → **Deploy Terraform - OIDC**:
1. Seleccionar cuenta (`connectivity` | `workloads`)
2. Seleccionar acción (`plan` | `apply` | `destroy`)
3. Seleccionar entorno (`dev` | `prod`) si la cuenta es workloads
4. Ejecutar workflow

El pipeline resuelve automáticamente el rol de despliegue cross-account.

### Despliegue local

```bash
cd accounts/connectivity
terraform init \
  -backend-config="bucket=<nombre-bucket>" \
  -backend-config="key=accounts/connectivity/terraform.tfstate" \
  -backend-config="region=us-east-1"
terraform plan
```

---

## Estado del proyecto

### Implementado

- [x] Diseño de arquitectura multicuenta hub-spoke (3 cuentas, 2 OUs)
- [x] Remote state en cuenta Tooling (S3 + versionado + cifrado + locking nativo)
- [x] Script de bootstrap/destroy para state remoto
- [x] Pipeline CI/CD con OIDC y cross-account role assumption
- [x] Resolución automática de rol y variables de red por cuenta/entorno en el pipeline
- [x] Variables de red externalizadas a GitHub repo variables (sin defaults en Terraform)
- [x] Módulo VPC con soporte multi-VPC, subnets dinámicas y output de TGW attachments
- [x] Módulo Transit Gateway (attachments reutilizable con for_each)
- [x] Módulo S3 reutilizable (versionado, cifrado, public access block)
- [x] Cuenta Connectivity: VPC hub + Transit Gateway + Internet Gateway + NAT Gateway
- [x] Cuenta Connectivity: route tables con rutas dinámicas a spokes (flatten + for_each)
- [x] Cuenta Workloads: VPC spokes + TGW attachment via remote state
- [x] Cuenta Workloads: route tables de app/db → TGW (excluyendo subnets de attachment)
- [x] Terraform workspaces para separación de entornos (dev/prod)

### Pendiente

- [ ] Módulo CloudFront (CDN)
- [ ] Módulos de compute (EC2, ASG, ALB)
- [ ] Módulos de base de datos (RDS, DocumentDB)
- [ ] AWS RAM para compartir subnets cross-account
- [ ] SCPs (Service Control Policies) por OU
- [ ] AWS Config + Security Hub

---

> **Nota sobre testing:** AWS Organizations desactiva el free tier de las cuentas miembro. Debido a la limitación de créditos, solo se realizaron pruebas funcionales sobre la capa de networking (VPCs, Transit Gateway, routing). Los módulos de compute (EC2, ASG, ALB) y base de datos (RDS, DocumentDB) están definidos en el código pero no han sido desplegados ni validados en un entorno real.
