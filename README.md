# AWS SSM Parameter Store

노트북에 export된 환경변수를 AWS Systems Manager Parameter Store에 저장합니다. 기존 상위 폴더의 Proxmox Terraform과 별도 state를 사용하는 독립 구성입니다. Terraform 명령은 반드시 이 폴더에서 실행하세요.

## 준비

- Terraform 1.11 이상, 2.0 미만. Provider 버전은 `.terraform.lock.hcl`로 고정합니다.
- 아래 환경변수 변환 예제는 Bash/Zsh와 Python 3를 사용합니다.
- AWS 인증: 노트북의 `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, 임시 인증일 경우 `AWS_SESSION_TOKEN`을 사용합니다. 또는 이미 설정한 `AWS_PROFILE`을 사용합니다. 코드에 키를 입력하지 않습니다.
- 리전: `export AWS_REGION=ap-northeast-2` (원하는 리전으로 변경).
- 실행 주체에는 대상 경로에 대한 `ssm:PutParameter`, `ssm:GetParameter`, `ssm:DeleteParameter`, `ssm:ListTagsForResource`, `ssm:AddTagsToResource`, `ssm:RemoveTagsFromResource` 권한과 `ssm:DescribeParameters` 권한이 필요합니다. `DescribeParameters`는 `Resource: "*"`로 허용하고, 나머지는 대상 parameter ARN 경로로 제한하세요. 사용자 관리 KMS 키를 쓰면 키 정책과 IAM에서 암호화·복호화 권한도 필요합니다. 이 구성은 IAM 사용자를 만들거나 권한을 부여하지 않습니다.

## 실행

### AWS SSO로 GHCR 인증 정보 저장

현재 provider 코드는 SSO 프로필을 그대로 사용할 수 있습니다. `aws configure sso`를 실행한 환경에서 프로필 이름을 지정하세요. 이미 로그인되어 있다면 다시 로그인할 필요는 없으며, 세션이 만료되었을 때 `aws sso login --profile "$AWS_PROFILE"`을 실행합니다.

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
export AWS_PROFILE=homelab # 사용할 SSO 프로필명
export AWS_REGION=ap-northeast-2 # SSM을 생성할 리전
aws sts get-caller-identity
```

출력에서 대상 계정과 역할을 확인하세요. 기존 `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` 환경변수가 설정되어 있으면 프로필 대신 사용될 수 있으므로 SSO를 사용할 터미널에서는 해제하세요. SSO 로그인 리전과 SSM 생성 리전은 서로 다를 수 있습니다. 다른 컴퓨터나 컨테이너에서 실행할 경우 그 환경에도 SSO 설정과 로그인이 필요합니다.

새 구성이라면 아래 예제를 복사합니다. 이미 `terraform.tfvars`가 있으면 덮어쓰지 말고 필요한 항목을 병합하세요. 기존에 관리하던 파라미터를 목록에서 제거하면 삭제 계획이 생깁니다.

```bash
cp -n terraform.ghcr.tfvars.example terraform.tfvars
```

예제는 `/homelab/ghcr/GHCR_USERNAME`, `/homelab/ghcr/GHCR_TOKEN`을 모두 `SecureString`으로 저장합니다. 경로와 태그는 환경에 맞게 수정하세요. `GHCR_USERNAME`에는 토큰을 발급한 GitHub 사용자명을 넣습니다. GHCR용 토큰은 **Personal access token (classic)**을 사용하며, 이미지 pull에는 `read:packages`, push에는 `write:packages` 권한이 필요합니다. 조직에서 GitHub SSO를 요구하면 토큰도 해당 조직에 승인해야 합니다. 이는 AWS SSO 로그인과 별개입니다. [GitHub 공식 인증 안내](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-to-the-container-registry)

`scripts/apply-ghcr.sh`를 실행하면 GitHub 사용자명과 토큰을 입력받습니다. 토큰 입력은 화면에 표시되지 않습니다. 이미 export된 `GHCR_USERNAME`, `GHCR_TOKEN`이 있으면 해당 값은 다시 묻지 않고 사용합니다. 기본 프로필은 `homelab`, 기본 리전은 `ap-northeast-2`이며 `AWS_PROFILE`, `AWS_REGION`으로 변경할 수 있습니다. AWS 인증 확인 → Terraform 초기화·검증 → 계획 표시 순서로 진행하고, `yes`를 입력하면 적용합니다. GHCR 두 항목 전용 스크립트이므로 `terraform.tfvars`의 `parameters`에도 이 두 항목만 있어야 합니다.

환경변수를 미리 설정하지 않아도 다음 명령 하나로 실행할 수 있습니다. 토큰 프롬프트에는 토큰 이름이 아닌 발급받은 실제 토큰 값을 붙여 넣으세요. 토큰을 명령줄에 직접 적지 않으므로 셸 기록에 남지 않습니다.

```bash
bash scripts/apply-ghcr.sh
```

스크립트에서 입력한 값은 해당 실행 안에서만 사용하며 종료 후 부모 터미널에 남지 않습니다. 기존 터미널에서 직접 export했다면 작업 후 `unset GHCR_USERNAME GHCR_TOKEN`으로 해제하세요. 스크립트는 `source`하지 말고 Bash로 실행하세요. 비대화형 실행에서는 두 환경변수를 모두 export해야 합니다. 토큰 교체 시에는 `terraform.tfvars`의 `GHCR_TOKEN.value_version`을 올리고 새 토큰으로 다시 실행하세요. SSM에 저장된 인증 정보는 이미지 pull을 수행하는 서버나 배포 도구가 별도로 읽어 사용해야 합니다.

### 일반 환경변수 저장

```bash
cd aws-ssm
cp terraform.tfvars.example terraform.tfvars
export AWS_REGION=ap-northeast-2
```

`terraform.tfvars`에서 `parameter_prefix`, 파라미터 이름, 타입, 태그를 수정하세요. 예제는 `/myapp/dev/DB_HOST`와 `/myapp/dev/DB_PASSWORD`를 만듭니다. 실제 값은 이 파일에 넣지 않습니다. 타입을 생략하면 `SecureString`입니다. `StringList`는 쉼표로 구분한 문자열을 전달합니다. Standard tier를 사용하므로 값은 UTF-8 기준 4KB 이하여야 합니다.

노트북에 **이미 export한** `DB_HOST`, `DB_PASSWORD`를 아래처럼 전달합니다. 항목을 추가하면 `parameters`와 아래 `names`를 함께 수정하세요. 이 코드는 지정한 변수만 읽으며, 따옴표·줄바꿈을 JSON으로 안전하게 변환합니다.

```bash
# AWS_*는 provider가 직접 읽습니다.
# 일반 환경변수는 TF_VAR_parameter_values라는 JSON 객체로 전달합니다.
if parameter_values_json="$(python3 - <<'PY'
import json
import os
import sys

names = ("DB_HOST", "DB_PASSWORD")
missing = [name for name in names if not os.environ.get(name)]
if missing:
    sys.exit("설정되지 않았거나 비어 있는 환경변수: " + ", ".join(missing))
print(json.dumps({name: os.environ[name] for name in names}))
PY
)"; then
  export TF_VAR_parameter_values="$parameter_values_json"
  unset parameter_values_json
else
  unset TF_VAR_parameter_values parameter_values_json
  # 필요한 환경변수를 설정하고 이 블록을 다시 실행하세요.
fi

terraform init
terraform fmt -check
terraform validate
terraform plan -input=false -out=ssm.tfplan
# 계획 확인 후, 같은 환경변수를 유지한 터미널에서 실행
terraform apply ssm.tfplan

unset TF_VAR_parameter_values
```

선택적으로 `aws sts get-caller-identity`로 사용할 계정을 먼저 확인할 수 있습니다. Terraform은 실행한 컴퓨터의 환경변수만 읽습니다. 다른 서버에서 실행하면 노트북의 환경변수가 자동 전달되지 않습니다. `.env` 파일도 자동으로 읽지 않습니다.

## 값 변경

항목별로 다른 경로와 태그가 필요하면 `parameters`의 해당 항목에 `prefix`와 `tags`를 지정할 수 있습니다. 지정하지 않은 항목은 공통 `parameter_prefix`를 그대로 사용합니다. 항목별 태그는 같은 이름의 공통 태그를 덮어씁니다.

```hcl
CLOUDFLARE_TOKEN = {
  prefix        = "/homelab/cloudflare"
  tags          = { Service = "cloudflare" }
  value_version = 1
}
```

기존 파라미터의 경로를 변경하면 교체가 계획될 수 있으므로 적용 전에 삭제 항목을 확인하세요.

1. 노트북의 원본 환경변수를 수정하고 위 JSON 변환 블록을 다시 실행합니다.
2. 해당 항목의 `value_version`을 `1` → `2`처럼 올립니다.
3. `terraform plan -input=false -out=ssm.tfplan`으로 새 계획을 만들고 `terraform apply ssm.tfplan`을 실행합니다.

`value_version`은 AWS가 부여하는 Parameter Store 버전과 별개인 Terraform 변경 트리거입니다. **환경변수 값만 바꾸면 Terraform이 변경을 감지하지 못합니다.** 타입·설명·KMS 키 등 파라미터 설정을 바꿀 때도 `value_version`을 올려 현재 값을 함께 전송하세요. 콘솔에서 수정한 값도 자동 비교·복구하지 않습니다.

`parameter_values`는 `sensitive` + `ephemeral`, 리소스 입력은 `value_wo`를 사용합니다. 새로 만드는 파라미터의 입력값을 state와 저장된 plan에 남기지 않으며, 출력에는 경로와 ARN만 포함합니다. 저장된 plan을 apply할 때도 환경변수가 필요합니다. 계획 이후 값을 바꾸면 apply에 전달되는 값도 달라지므로 동일한 값을 유지하세요. 디버그 로그와 셸 추적(`TF_LOG`, `set -x`)은 비밀값을 노출할 수 있으므로 비밀값을 다룰 때 사용하지 마세요.

같은 경로에 이미 있는 파라미터는 신규 생성 시 자동 덮어쓰지 않습니다. 기존 파라미터를 가져오는 `terraform import`는 값이 state에 들어갈 수 있으므로 이 신규 생성용 예제와 별도로 검토해야 합니다. 파라미터를 `parameters`에서 제거하거나 `terraform destroy`를 실행하면 AWS에서도 삭제됩니다.

## GitHub에 올리기

커밋 대상은 `.tf`, `tests/`, `README.md`, `.gitignore`, `.terraform.lock.hcl`, 값이 없는 `terraform.tfvars.example`입니다. 실제 `terraform.tfvars`, `.env`, `.terraform/`, state, plan은 제외합니다. `.gitignore`는 이 폴더를 독립 저장소로 복사해도 동작합니다.

**현재 상위 저장소는 `credentials.auto.tfvars`, `terraform.tfstate`, `terraform.tfstate.backup`, `.terraform/`를 이미 추적하고 있습니다.** `.gitignore`를 추가해도 기존 추적과 과거 커밋은 사라지지 않습니다. 이 저장소 전체를 그대로 GitHub에 push하지 마세요. AWS 코드만 올릴 경우 아래 파일만 새 폴더로 복사해 새 Git 저장소를 만드는 방법이 간단합니다. 상위 `.git`은 복사하지 않습니다.

```bash
# aws-ssm 폴더에서 실행. 새 빈 폴더를 지정하세요.
mkdir ../aws-ssm-publish
cp ./*.tf README.md .gitignore .terraform.lock.hcl terraform.tfvars.example ../aws-ssm-publish/
cp -R tests ../aws-ssm-publish/
cd ../aws-ssm-publish
git init
git add .
git diff --cached --stat
# 내용을 확인한 후 commit하고 GitHub 원격 저장소를 연결하세요.
```

기존 저장소를 계속 사용하려면 민감 파일의 추적 해제와 과거 커밋 정리가 별도로 필요합니다. 실제 자격증명이 이미 외부에 공개됐다면 해당 자격증명도 교체하세요. 이 작업에서는 기존 파일이나 Git 기록을 변경하지 않습니다.

## 로컬 검증

`terraform init` 후 `terraform test`로 AWS에 연결하지 않는 mock provider 테스트를 실행할 수 있습니다. 파라미터 경로와 기본 암호화 타입, 빈 값·누락·목록에 없는 입력값·잘못된 버전 번호 거부를 확인합니다. 실제 AWS IAM/KMS 권한과 API 동작은 실제 계정에서 `plan` 및 `apply`할 때 확인해야 합니다.

## 공식 문서

- [AWS CLI SSO 프로필 설정 및 로그인](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html)
- [AWS provider 환경변수 인증](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#environment-variables)
- [SSM parameter와 value_wo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter)
- [Terraform 쓰기 전용 인수](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/write-only)
- [Terraform 입력변수](https://developer.hashicorp.com/terraform/language/values/variables)
