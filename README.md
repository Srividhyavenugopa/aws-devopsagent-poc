# AWS DevOps Agent POC

A beginner-friendly project to learn AWS DevOps Agent concepts:
- Terraform for infrastructure
- Docker + ECR for containerization
- ECS Fargate for running the app
- GitHub Actions for CI/CD
- CloudWatch for monitoring
- AWS DevOps Agent for AI-assisted troubleshooting

---

## Project Structure

```
aws-devopsagent-poc/
├── app/
│   ├── app.js          # Node.js Hello World app
│   ├── package.json
│   └── Dockerfile
├── terraform/
│   ├── main.tf         # ECR, ECS, CloudWatch, IAM resources
│   ├── variables.tf
│   └── outputs.tf
├── .github/
│   └── workflows/
│       └── deploy.yml  # CI/CD pipeline
├── scripts/
│   └── push-image.sh   # Manual ECR push helper
└── fault/
    └── app-with-fault.js  # Broken app for DevOps Agent exercise
```

---

## Prerequisites

```bash
# Install tools
brew tap hashicorp/tap
brew install hashicorp/tap/terraform awscli gh node docker

# Configure AWS CLI - if using Azure AD SSO (AWS IAM Identity Center):
aws configure sso
# Follow the prompts: SSO start URL, SSO region, account, role, output format
# Then to activate the profile for the session:
export AWS_PROFILE=your-sso-profile-name
aws sts get-caller-identity   # verify it works
```

You need an AWS account. Free tier is sufficient for this project.

---

## Step 1: Clone and Push to GitHub

```bash
cd aws-devopsagent-poc
gh repo create aws-devopsagent-poc --public --source=. --push
```

---

## Step 2: Deploy Infrastructure with Terraform

```bash
cd terraform
terraform init
terraform plan    # review what will be created
terraform apply   # type 'yes' to confirm
```

Note the outputs — you'll need them:
```
ecr_repository_url = "123456789.dkr.ecr.us-east-1.amazonaws.com/hello-devops"
ecs_cluster_name   = "hello-devops-cluster"
cloudwatch_log_group = "/ecs/hello-devops"
```

---

## Step 3: Build and Push Docker Image to ECR

```bash
cd scripts
chmod +x push-image.sh
./push-image.sh
```

Or manually:
```bash
ECR_URL=$(cd ../terraform && terraform output -raw ecr_repository_url)
REGION=us-east-1

aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ECR_URL

cd ../app
docker build -t hello-devops .
docker tag hello-devops:latest $ECR_URL:latest
docker push $ECR_URL:latest
```

---

## Step 4: Configure GitHub Actions with IAM Role (OIDC — no access keys needed)

This project uses GitHub OIDC to assume an IAM role — no long-lived credentials.
Your personal Azure AD SSO login is separate from this; GitHub Actions gets its own trust.

### 4a: Add GitHub as an OIDC Identity Provider in AWS

Do this once per AWS account. In the AWS Console:

1. Go to **IAM > Identity providers > Add provider**
2. Select **OpenID Connect**
3. Provider URL: `https://token.actions.githubusercontent.com`
4. Click **Get thumbprint**
5. Audience: `sts.amazonaws.com`
6. Click **Add provider**

Or via CLI:
```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 4b: Create an IAM Role for GitHub Actions

1. Go to **IAM > Roles > Create role**
2. Select **Web identity**
3. Identity provider: `token.actions.githubusercontent.com`
4. Audience: `sts.amazonaws.com`
5. Add condition: `token.actions.githubusercontent.com:sub` = `repo:YOUR_GITHUB_USERNAME/aws-devopsagent-poc:ref:refs/heads/main`
6. Attach permissions: `AmazonEC2ContainerRegistryPowerUser` + `AmazonECS_FullAccess`
7. Name the role: `github-actions-hello-devops`
8. Copy the **Role ARN** (e.g. `arn:aws:iam::123456789012:role/github-actions-hello-devops`)

### 4c: Add GitHub Secrets

In your GitHub repo go to **Settings > Secrets and variables > Actions** and add:

| Secret Name | Value |
|---|---|
| `AWS_ROLE_ARN` | Role ARN from step 4b above |
| `ECR_URL` | Output from `terraform output ecr_repository_url` |

> **Note for Azure SSO users:** Your personal `aws configure` profile uses Azure AD — that's fine for running Terraform locally. GitHub Actions uses its own separate trust (OIDC) and never touches your Azure credentials.

---

## Step 5: Trigger a Deploy

Make any change and push:
```bash
echo "# trigger deploy" >> app/app.js
git add . && git commit -m "trigger deploy"
git push
```

Watch the GitHub Actions tab — it will build and push the Docker image automatically.

---

## Step 6: Set Up AWS DevOps Agent

AWS DevOps Agent is a standalone service that uses an **Agent Space** architecture — a logical container defining the AWS accounts, tools, and users the agent can access.

### 6a: Create an Agent Space

1. Go to **AWS Console > AWS DevOps Agent**
2. Click **Create Agent Space**
3. Give it a name (e.g. `hello-devops-space`)
4. Select the **AWS account** the agent should have access to
5. Set **access boundaries** — at minimum grant read access to:
   - CloudWatch Logs (log group `/ecs/hello-devops`)
   - ECS (cluster `hello-devops-cluster`)

### 6b: Connect Integrations

Inside your Agent Space, configure integrations:

| Integration | Purpose |
|---|---|
| Amazon CloudWatch | Read logs, metrics, traces for root cause analysis |
| GitHub | (Optional) Auto-create PRs with fixes |
| Slack | (Optional) Auto-create incident channels |
| Jira / ServiceNow | (Optional) Auto-generate tickets |

### 6c: Configure Agent Behavior

- **Alert Correlation**: enables automatic grouping of related CloudWatch alarms into single incidents
- **Root Cause Analysis**: AI-powered investigation across metrics, logs, and traces
- **Prevention mode**: analyzes historical patterns to suggest architecture improvements

### 6d: Access the Operator Web App

The Agent Space has two interfaces:
- **AWS Management Console**: admin configuration
- **Operator Web App**: where your ops team runs investigations and reviews recommendations

Open the Operator Web App URL shown in your Agent Space dashboard — this is where you'll trigger investigations in Step 8.

---

## Step 7: Inject a Fault (DevOps Agent Exercise)

Copy the broken app over the good one:
```bash
cp fault/app-with-fault.js app/app.js
git add . && git commit -m "inject fault for devops agent exercise"
git push
```

The app will crash randomly. CloudWatch will log errors like:
```
ERROR: Simulated fault triggered!
```

Then in the **Operator Web App** for your Agent Space:

1. Click **New Investigation** (or wait for the agent to auto-detect the CloudWatch alarm)
2. Ask in natural language:
   > "App is crashing intermittently. Check CloudWatch log group /ecs/hello-devops and perform root cause analysis."
3. The agent will:
   - Correlate CloudWatch log errors into a single incident
   - Perform topology-aware analysis across ECS + logs
   - Generate a **Root Cause Analysis report** identifying the `throw new Error(...)` line
   - Suggest a mitigation plan
   - (If GitHub is connected) Submit a PR removing the fault

4. Review the agent's findings in the **DevOps Center** — it gives a birdseye view of your app topology and the incident timeline
5. Merge the PR — your app is fixed!

---

## Step 8: Tear Down (avoid AWS charges)

```bash
cd terraform
terraform destroy   # type 'yes' to confirm
```

Also delete the ECR images first if destroy fails:
```bash
aws ecr batch-delete-image \
  --repository-name hello-devops \
  --image-ids imageTag=latest
```

---

## What You Learned

| Concept | Where |
|---|---|
| Infrastructure as Code | `terraform/` |
| Containerization | `app/Dockerfile` |
| Container Registry | ECR (created by Terraform) |
| Serverless Containers | ECS Fargate |
| CI/CD Pipeline | `.github/workflows/deploy.yml` |
| Observability | CloudWatch log group |
| AI Ops — Agent Space | AWS DevOps Agent |
| Incident RCA | DevOps Agent Operator Web App |
| Prevention recommendations | DevOps Agent pattern analysis |

---

## Troubleshooting

**`terraform apply` fails with permissions error**
- Make sure your IAM user has `AdministratorAccess` or at minimum ECS, ECR, IAM, and CloudWatch permissions.

**Docker push fails**
- Re-run the ECR login command — tokens expire after 12 hours.

**GitHub Actions fails**
- Check that all 3 secrets are set correctly in the repo settings.

**ECS task keeps stopping**
- Check CloudWatch logs: `aws logs tail /ecs/hello-devops --follow`
