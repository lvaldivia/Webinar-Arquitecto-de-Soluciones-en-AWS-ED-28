#!/usr/bin/env bash
# Construye la AMI desde backend/ local. Las EC2 del ASG no usan user data.
# Uso: bash scripts/build-api-ami.sh
# BASE_AMI_ID=ami-... permite reutilizar una AMI propia como caché de Docker.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/tf-outputs.sh"
use_tf_profile
export AWS_REGION="$(tf_output region)"
export AWS_CLI_OUTPUT_ENCODING=UTF-8 AWS_CLI_FILE_ENCODING=UTF-8
export AWS_PAGER=""

log() { echo "[build-ami] $*"; }
aws_cmd() { MSYS_NO_PATHCONV=1 aws "$@"; }
native_path() { if command -v cygpath >/dev/null; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
for tool in aws terraform; do command -v "$tool" >/dev/null || { echo "Falta $tool" >&2; exit 1; }; done
if command -v python3 >/dev/null && python3 --version >/dev/null 2>&1; then PYTHON=python3; else PYTHON=python; fi
"$PYTHON" --version >/dev/null

subnet="$(tf_output builder_subnet_id)"
security_group="$(tf_output builder_security_group_id)"
instance_profile="$(tf_output builder_instance_profile)"
group="$(tf_output asg_name)"
target_group="$(tf_output target_group_arn)"
instance_type="$(tf_output api_instance_type)"
prefix="${group%-asg}"
if [[ -z "$subnet" || -z "$security_group" || -z "$instance_profile" || -z "$target_group" || -z "$instance_type" ]]; then
  echo "Falta la infraestructura base. Ejecuta bash scripts/infra-up.sh." >&2
  exit 1
fi
base_ami="${BASE_AMI_ID:-$(aws_cmd ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)}"
version="$(git -C "$SCRIPT_DIR/.." rev-parse --short HEAD 2>/dev/null || echo local)-$(date -u +%Y%m%d%H%M%S)"
temp_dir="$(mktemp -d)"
builder=""
cleanup() {
  if [[ -n "$builder" ]]; then
    aws_cmd ec2 terminate-instances --instance-ids "$builder" --output json >/dev/null || true
    log "Constructor temporal terminado: $builder"
  fi
  rm -f "$temp_dir/commands.json" "$temp_dir/status.json"
  rmdir "$temp_dir"
}
trap cleanup EXIT

# JSON y tar se generan sin interpolar código de shell procedente de los archivos.
"$PYTHON" - "$SCRIPT_DIR/../backend" "$temp_dir/commands.json" "$version" "$group" "$target_group" <<'PY'
import base64, io, json, pathlib, shlex, sys, tarfile
root, output, version, group, target = sys.argv[1:]
root = pathlib.Path(root)
archive = io.BytesIO()
with tarfile.open(fileobj=archive, mode='w:gz') as tar:
    for name in ('Dockerfile', 'requirements.txt'):
        tar.add(root / name, arcname=name)
    for source in sorted((root / 'app').rglob('*.py')):
        tar.add(source, arcname=source.relative_to(root).as_posix())
encoded = base64.b64encode(archive.getvalue()).decode('ascii')
q = shlex.quote
commands = [
    'set -eu',
    'cloud-init status --wait',
    'command -v docker >/dev/null 2>&1 || dnf install -y docker',
    'systemctl enable --now docker',
    'docker rm -f grimorio-api >/dev/null 2>&1 || true',
    'build_dir=$(mktemp -d /tmp/grimorios-api-build.XXXXXX)',
    "printf '%s' '" + encoded + "' | base64 -d | tar -xz -C \"$build_dir\"",
    'docker build -t grimorio-api:latest "$build_dir"',
    'rm -rf "$build_dir"',
    'docker run -d --name grimorio-api --restart always -p 8080:8080 '
    + '-e ' + q('APP_VERSION=' + version) + ' -e ' + q('AUTOSCALING_GROUP_NAME=' + group)
    + ' -e ' + q('TARGET_GROUP_ARN=' + target)
    + ' --log-opt max-size=10m --log-opt max-file=3 grimorio-api:latest',
    'curl --retry 30 --retry-all-errors --retry-delay 1 --max-time 5 -fsS http://localhost:8080/health',
    'curl -fsS http://localhost:8080/api/info',
    'docker stop grimorio-api',
    'cloud-init clean --logs',
    'truncate -s 0 /etc/machine-id',
    'if [ -f /var/lib/dbus/machine-id ] && [ ! -L /var/lib/dbus/machine-id ]; then truncate -s 0 /var/lib/dbus/machine-id; fi',
    'sync',
]
pathlib.Path(output).write_text(json.dumps({'commands': commands, 'executionTimeout': ['1200']}), encoding='utf-8')
PY

log "Creando constructor temporal desde $base_ami (sin user data)..."
builder="$(aws_cmd ec2 run-instances --image-id "$base_ami" --instance-type "$instance_type" \
  --subnet-id "$subnet" --security-group-ids "$security_group" \
  --iam-instance-profile "Name=$instance_profile" \
  --metadata-options 'HttpTokens=required,HttpPutResponseHopLimit=2' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$prefix-ami-builder}]" \
  --count 1 --query 'Instances[0].InstanceId' --output text)"
log "Constructor: $builder; esperando Session Manager..."
online=false
for _ in $(seq 1 60); do
  status="$(aws_cmd ssm describe-instance-information --filters "Key=InstanceIds,Values=$builder" --query 'InstanceInformationList[0].PingStatus' --output text)"
  if [[ "$status" == Online ]]; then online=true; break; fi
  sleep 5
done
[[ "$online" == true ]] || { echo 'SSM no llegó a estar disponible.' >&2; exit 1; }
command_id="$(aws_cmd ssm send-command --instance-ids "$builder" --document-name AWS-RunShellScript \
  --parameters "file://$(native_path "$temp_dir/commands.json")" --query Command.CommandId --output text)"
status=Pending
for _ in $(seq 1 120); do
  status="$(aws_cmd ssm list-command-invocations --command-id "$command_id" --query 'CommandInvocations[0].Status' --output text)"
  case "$status" in Success|Failed|Cancelled|TimedOut) break;; esac
  log "Preparando Docker y la API: $status"
  sleep 10
done
if [[ "$status" != Success ]]; then
  aws_cmd ssm get-command-invocation --command-id "$command_id" --instance-id "$builder" --output json
  exit 1
fi
log 'API comprobada. Deteniendo el servidor para capturar discos consistentes...'
aws_cmd ec2 stop-instances --instance-ids "$builder" --output json >/dev/null
aws_cmd ec2 wait instance-stopped --instance-ids "$builder"
ami="$(aws_cmd ec2 create-image --instance-id "$builder" --name "$prefix-api-$version" \
  --tag-specifications "ResourceType=image,Tags=[{Key=Project,Value=$prefix},{Key=ManagedBy,Value=grimorios-ami-builder}]" \
  "ResourceType=snapshot,Tags=[{Key=Project,Value=$prefix},{Key=ManagedBy,Value=grimorios-ami-builder}]" \
  --query ImageId --output text)"
log "AMI: $ami; esperando disponibilidad..."
available=false
for _ in $(seq 1 180); do
  state="$(aws_cmd ec2 describe-images --image-ids "$ami" --query 'Images[0].State' --output text)"
  if [[ "$state" == available ]]; then available=true; break; fi
  [[ "$state" != failed ]] || { echo "Falló la AMI $ami" >&2; exit 1; }
  sleep 10
done
[[ "$available" == true ]] || { echo "La AMI $ami sigue pendiente; consulta su estado en EC2." >&2; exit 1; }
printf '{"api_ami_id":"%s"}\n' "$ami" > "$INFRA_DIR/api-ami.auto.tfvars.json"
log "Lista: $ami. Configuración guardada en infra/api-ami.auto.tfvars.json."
