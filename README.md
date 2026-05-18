# AWS Landing Zone — Terraform

![Terraform](https://img.shields.io/badge/Terraform_1.15-7B42BC?style=flat&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-232F3E?style=flat&logo=amazonwebservices&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat&logo=githubactions&logoColor=white)

Implementación de una AWS Landing Zone multicuenta con Terraform. Arquitectura diseñada para entornos productivos con segmentación por función, networking centralizado y despliegue automatizado vía CI/CD con OIDC.

---

## Arquitectura

![Diagrama de Arquitectura](diagrams/arquitectura.png)

### Cuentas y Organizational Units

| Cuenta | OU | Propósito |
|--------|-----|-----------|
| **Root** | — | AWS Organizations, Identity Center (SSO), Cost Explorer |
| **Tooling** | Share Resources | Remote state de Terraform (S3 con versionado, cifrado y locking nativo) |
| **Connectivity** | Share Resources | Networking centralizado: VPC Ingress/Egress, VPC Prod, Transit Gateway, NAT |
| **Prod** | Workloads | Cargas de trabajo: API Gateway, ALB, ASG (EC2), RDS, DocumentDB, CloudFront, S3 |

### Networking (Connectivity Account)

Toda la infraestructura de red vive en la cuenta **Connectivity**, desplegada en dos AZs (`us-east-1a`, `us-east-1b`):

- **VPC Ingress/Egress** (`10.250.0.0/16`): maneja todo el tráfico de entrada/salida. Subnets públicas (`/24`) con Internet Gateway y NAT Gateway, subnets privadas TGW (`/28`) para los ENIs del Transit Gateway.
- **VPC Prod** (`10.251.0.0/16`): subnets privadas segmentadas por capa — TGW (`/28`), aplicación (`/24`) y base de datos (`/24`).
- **Transit Gateway**: conecta ambas VPCs. Compartido entre cuentas vía **AWS RAM** para que Prod despliegue recursos en las subnets de la VPC Prod sin gestionar networking.

### Compute y Aplicación (Prod Account)

```
Internet → CloudFront (CDN) → S3 (estáticos)
Internet → API Gateway → ALB → Auto Scaling Group (EC2) → RDS / DocumentDB
```

### CI/CD

```
GitHub Actions → OIDC → AWS (tokens temporales, sin access keys estáticas)
```

Pipeline con `workflow_dispatch` que permite seleccionar cuenta (`connectivity` | `production`) y acción (`plan` | `apply` | `destroy` | `unlock`).

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
| **CI/CD** | GitHub Actions con autenticación OIDC (sin credenciales estáticas) |
| **State** | S3 backend en cuenta Tooling dedicada (versionado + locking nativo) |
| **Acceso** | AWS Identity Center (SSO) para acceso por CLI |
| **Región** | `us-east-1` |

---

## Estructura de carpetas

```
.
├── .github/workflows/
│   └── deploy.yml                  # Pipeline CI/CD con OIDC
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
│   │   ├── provider.tf
│   │   ├── backend.tf
│   │   ├── main.tf                 # Invoca módulo VPC (IngresEgress + Prod)
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── production/
│       ├── provider.tf
│       ├── backend.tf
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── modules/
    ├── networking/
    │   ├── vpc/                    # VPC + Subnets (for_each, multi-VPC)
    │   └── transit-gateway/
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

**¿Por qué AWS RAM para compartir subnets?**  
Resource Access Manager permite compartir subnets a otras cuentas de la misma organización, permitiendo que Prod despliegue recursos en subnets gestionadas centralmente por Connectivity sin duplicar infraestructura de red.

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

### Bootstrap del state remoto

```bash
cd accounts/tooling
cp terraform.example.tfvars terraform.tfvars  # Editar con valores reales
./stateUtil.sh bootstrap <aws-profile>
```

Esto crea el bucket S3, migra el state de local a remoto y genera el `config.hcl` con la configuración del backend.

### Despliegue manual (CI/CD)

Desde GitHub → Actions → **Deploy Terraform - OIDC**:
1. Seleccionar cuenta (`connectivity` | `production`)
2. Seleccionar acción (`plan` | `apply` | `destroy`)
3. Ejecutar workflow

### Despliegue local

```bash
cd accounts/connectivity
terraform init \
  -backend-config="bucket=<nombre-bucket>" \
  -backend-config="key=connectivity/terraform.tfstate" \
  -backend-config="region=us-east-1"
terraform plan
```

---

## Estado del proyecto

### Implementado

- [x] Diseño de arquitectura multicuenta (4 cuentas, 2 OUs)
- [x] Remote state en cuenta Tooling (S3 + versionado + cifrado + locking nativo)
- [x] Script de bootstrap/destroy para state remoto
- [x] Pipeline CI/CD con OIDC (plan, apply, destroy, unlock)
- [x] Módulo VPC con soporte multi-VPC y subnets dinámicas
- [x] Módulo S3 reutilizable (versionado, cifrado, public access block)
- [x] Cuenta Connectivity con VPCs desplegadas (Ingress/Egress + Prod)

### En progreso

- [ ] Módulo Transit Gateway + attachments + route tables
- [ ] Módulo CloudFront (CDN)
- [ ] Internet Gateway + NAT Gateway en VPC Ingress/Egress
- [ ] Route tables y asociaciones de subnets

### Pendiente

- [ ] Módulos de compute (EC2, ASG, ALB)
- [ ] Módulos de base de datos (RDS, DocumentDB)
- [ ] Cuenta Production con recursos desplegados
- [ ] AWS RAM para compartir subnets cross-account
- [ ] SCPs (Service Control Policies) por OU
- [ ] AWS Config + Security Hub
