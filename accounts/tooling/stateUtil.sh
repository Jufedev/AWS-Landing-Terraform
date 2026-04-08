#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
AWS_PROFILE="${2:-}"

TF_BACKEND_FILE="backend.generated.tf"
LOCAL_STATE="local.tfstate"
S3_CONFIG="config.hcl"

usage() {
  echo "Uso:"
  echo "  $0 bootstrap <aws-profile>"
  echo "  $0 destroy <aws-profile>"
}

write_local_backend() {
  cat > "${TF_BACKEND_FILE}" <<'EOF'
terraform {
  backend "local" {}
}
EOF
}

write_s3_backend() {
  cat > "${TF_BACKEND_FILE}" <<'EOF'
terraform {
  backend "s3" {}
}
EOF
}

require_args() {
  if [[ -z "${ACTION}" || -z "${AWS_PROFILE}" ]]; then
    usage
    exit 1
  fi

  if [[ "${ACTION}" != "bootstrap" && "${ACTION}" != "destroy" ]]; then
    usage
    exit 1
  fi
}

bootstrap() {
  echo "==> Usando perfil AWS: ${AWS_PROFILE}"
  export AWS_PROFILE="${AWS_PROFILE}"

  echo "==> Inicializando con backend local..."
  write_local_backend
  terraform init -reconfigure -input=false -backend-config="path=${LOCAL_STATE}"

  echo "==> Creando recursos..."
  terraform apply -auto-approve -input=false

  echo "==> Leyendo outputs..."
  BUCKET_NAME="$(terraform output -raw s3_bucket_name)"
  REGION="$(terraform output -raw region)"

  echo "    Bucket: ${BUCKET_NAME}"
  echo "    Region: ${REGION}"

  echo "==> Generando config para S3..."
  cat > "${S3_CONFIG}" <<EOF
bucket       = "${BUCKET_NAME}"
key          = "global/terraform.tfstate"
region       = "${REGION}"
encrypt      = true
use_lockfile = true
profile      = "${AWS_PROFILE}"
EOF

  echo "==> Migrando state a S3..."
  write_s3_backend
  terraform init -migrate-state -force-copy -input=false -backend-config="${S3_CONFIG}"

  echo "✅ State migrado a S3."
}

destroy_all() {
  echo "==> Usando perfil AWS: ${AWS_PROFILE}"
  export AWS_PROFILE="${AWS_PROFILE}"

  echo "==> Volviendo a backend local..."
  write_local_backend
  terraform init -migrate-state -force-copy -input=false -backend-config="path=${LOCAL_STATE}"

  echo "==> Destruyendo recursos..."
  terraform destroy -auto-approve -input=false

  echo "==> Limpiando archivos generados..."
  rm -f "${TF_BACKEND_FILE}" "${S3_CONFIG}" "${LOCAL_STATE}" "${LOCAL_STATE}.backup"

  echo "✅ Todo eliminado."
}

main() {
  require_args

  case "${ACTION}" in
    bootstrap)
      bootstrap
      ;;
    destroy)
      destroy_all
      ;;
  esac
}

main "$@"
