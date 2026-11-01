#!/usr/bin/env bash
# Run this script with Bash; do not source it.
set +x
set -euo pipefail

if (( $# > 0 )); then
  printf '사용법: bash scripts/apply-ghcr.sh (사용자명과 토큰은 실행 중 입력하거나 미리 export)\n' >&2
  exit 1
fi

unset TF_LOG TF_LOG_PATH TF_LOG_CORE TF_LOG_PROVIDER

for command in aws terraform python3; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf '필요한 명령을 찾을 수 없습니다: %s\n' "$command" >&2
    exit 1
  fi
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$script_dir/.."

if [[ ! -f terraform.tfvars ]]; then
  printf 'terraform.ghcr.tfvars.example을 terraform.tfvars로 복사하고 경로를 설정하세요.\n' >&2
  exit 1
fi

if [[ -z "${GHCR_USERNAME:-}" || -z "${GHCR_TOKEN:-}" ]]; then
  if [[ ! -t 0 ]]; then
    printf '터미널에서 실행해 사용자명과 토큰을 입력하거나 GHCR_USERNAME과 GHCR_TOKEN을 export하세요.\n' >&2
    exit 1
  fi
  if [[ -z "${GHCR_USERNAME:-}" ]]; then
    if ! IFS= read -r -p 'GitHub username: ' GHCR_USERNAME; then
      printf '\n사용자명 입력이 취소되었습니다.\n' >&2
      exit 1
    fi
  fi
  if [[ -z "${GHCR_TOKEN:-}" ]]; then
    if ! IFS= read -r -s -p 'GHCR token (발급받은 토큰 값): ' GHCR_TOKEN; then
      printf '\n토큰 입력이 취소되었습니다.\n' >&2
      exit 1
    fi
    printf '\n'
  fi
fi
export GHCR_USERNAME GHCR_TOKEN

# Serialize only the two GHCR variables; never print credentials to the terminal.
parameter_values_json="$(python3 - <<'PY'
import json
import os
import sys

names = ("GHCR_USERNAME", "GHCR_TOKEN")
missing = [name for name in names if not os.environ.get(name)]
if missing:
    sys.exit("설정되지 않았거나 비어 있는 환경변수: " + ", ".join(missing))
print(json.dumps({name: os.environ[name] for name in names}))
PY
)"
unset GHCR_USERNAME GHCR_TOKEN TF_VAR_parameter_values

# Prefer the selected SSO profile over inherited static credentials.
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
export AWS_PROFILE="${AWS_PROFILE:-homelab}"
export AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-northeast-2}}"
export AWS_DEFAULT_REGION="$AWS_REGION"

printf 'AWS 프로필: %s / 리전: %s\n' "$AWS_PROFILE" "$AWS_REGION"
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" --no-cli-pager; then
  printf 'AWS 인증을 확인하세요. 세션이 만료됐다면 aws sso login --profile %s 실행 후 다시 시도하세요.\n' "$AWS_PROFILE" >&2
  exit 1
fi

export TF_VAR_parameter_values="$parameter_values_json"
unset parameter_values_json

terraform init -input=false
terraform validate
# Terraform displays the plan and requests "yes" before applying it.
terraform apply -input=true
