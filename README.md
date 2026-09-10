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

> **Corporate AWS accounts:** `sts:AssumeRoleWithWebIdentity` is often blocked by an SCP at the org level.
> If you hit this, **skip to [Step 5 → Option A](#step-5-deploy-the-app)** and push manually using your SSO credentials instead.

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

## Step 5: Deploy the App

> **Note:** GitHub Actions OIDC (`sts:AssumeRoleWithWebIdentity`) may be blocked by an SCP in corporate AWS accounts. Use the manual push approach below instead.

### Option A: Manual push using local SSO credentials (recommended for POC)

```bash
cd /Users/srividhya.venugopal/Documents/GitHubPersonal/aws-devopsagent-poc/scripts
chmod +x push-image.sh
./push-image.sh
```

This builds the Docker image, pushes it to ECR, and triggers an ECS redeploy using your existing Azure SSO credentials.

### Option B: GitHub Actions (requires SCP allow for sts:AssumeRoleWithWebIdentity)

Push any change to trigger the pipeline:
```bash
echo "# trigger deploy" >> app/app.js
git add . && git commit -m "trigger deploy"
git push
```

If you see `Not authorized to perform sts:AssumeRoleWithWebIdentity`, ask your AWS admin to allow `sts:AssumeRoleWithWebIdentity` in the organization SCP for your account.

---

## Step 6: Set Up AWS DevOps Agent

AWS DevOps Agent is a standalone service that uses an **Agent Space** architecture — a logical container defining the AWS accounts, tools, and users the agent can access.

### 6a: Create an Agent Space

1. Go to **AWS Console > AWS DevOps Agent**
2. Click **Create Agent Space**
3. Give it a name (e.g. `hello-devops-space`)
4. Select the **AWS account** the agent should have access to
5. AWS will auto-create IAM roles and begin **topology mapping** — this discovers relationships between your resources (ECS, CloudWatch, VPC, etc.)
6. Wait for the status to show **"Topology mapping complete"** — the count shows how many resource relationships were discovered

The Agent Space has 4 tabs:
- **Capabilities** — add external sources (Azure, etc.)
- **Web app** — access the Operator Web App + manage user access
- **Configuration** — view the agent's IAM role and settings
- **Summary report** — overview of investigations and findings

### 6b: Add Capabilities to your Agent Space

In your Agent Space, click **Add a capability**. This is where you register **external** sources. AWS-native services (CloudWatch, ECS, X-Ray) are automatically available within the same AWS account — no capability registration needed for them.

---

#### Amazon CloudWatch (automatic — no setup needed)

CloudWatch access is managed automatically by the `AWSServiceRoleForAIDevOps` service-linked role that AWS creates and manages. The agent discovers log groups, metrics, and alarms automatically during topology mapping — no manual IAM changes needed.

To enable the agent's **own activity logs** (optional but recommended):

1. Go to **Configuration tab > Log delivery > Add**
2. Log type: `APPLICATION_LOGS`
3. Destination log group: accept the default `/aws/vendedlogs/aidevops/...` (created automatically)
4. Click **Add**

To allow the agent to take **remediation actions** (not just read/investigate):

1. Go to **Configuration tab > Agent actions**
2. Toggle **Enable agent actions** ON
3. First add an Agent Actions role on the **Capabilities tab**
4. Every action the agent proposes requires your explicit approval before it runs

---

#### Azure Cloud (optional — for multi-cloud investigations)

If your app spans AWS and Azure:

1. Click **Add a capability > Azure Cloud > Register**
2. Provide your Azure tenant ID and authorize the connection
3. Note: *Registration provides access to all Agent Spaces* in the account

---

#### Other capabilities

Search **Add a capability** for available sources — the list includes third-party observability platforms, ticketing systems, and communication tools depending on your account's enabled features. Available options vary by region and whether your account has opted into preview features.

### 6c: Set Up CloudWatch Alarm to Auto-Trigger Investigations

This creates a custom metric filter on your app logs and a CloudWatch alarm. When the alarm fires, the DevOps Agent automatically starts an investigation.

**Step 1: Create a metric filter on the app log group**

```bash
aws logs put-metric-filter \
  --log-group-name /ecs/hello-devops \
  --filter-name ErrorCount \
  --filter-pattern "ERROR" \
  --metric-transformations \
    metricName=AppErrorCount,metricNamespace=HelloDevops,metricValue=1,defaultValue=0
```

This watches `/ecs/hello-devops` and increments a custom metric `HelloDevops/AppErrorCount` each time an ERROR line appears.

**Step 2: Create a CloudWatch alarm on that metric**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name hello-devops-errors \
  --alarm-description "Fires when app errors detected — triggers DevOps Agent investigation" \
  --metric-name AppErrorCount \
  --namespace HelloDevops \
  --statistic Sum \
  --period 60 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching
```

**Step 3: Verify the alarm was created**

```bash
aws cloudwatch describe-alarms \
  --alarm-names hello-devops-errors \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table
```

It should show `INSUFFICIENT_DATA` (normal — no data yet). It will switch to `ALARM` when errors occur.

**Step 4: Verify the Agent Space can see the alarm**

No manual connection needed — since your Primary AWS account (`300428143068`) is already **Valid** in the Capabilities tab, the agent automatically has access to all CloudWatch alarms in that account including `hello-devops-errors`.

To confirm:
1. Go to your `hello-devops-space` Agent Space → **Capabilities** tab
2. Under **Cloud > Primary source**, check the status shows **Valid**
3. The agent will auto-detect the alarm when it fires and start an investigation

> **Optional — enable agent remediation actions:**
> The **Actions role status** may show "Not configured". Click **Edit** next to the Primary source to configure this — it allows the agent to take remediation steps (restart tasks, update services) with your explicit approval.
>
> **Telemetry sources** (Datadog, Dynatrace) are optional — not needed for this POC.

### 6d: Configure Agent Behavior

- **Alert Correlation**: enables automatic grouping of related CloudWatch alarms into single incidents
- **Root Cause Analysis**: AI-powered investigation across metrics, logs, and traces
- **Prevention mode**: analyzes historical patterns to suggest architecture improvements

### 6d: Access the Operator Web App

1. In your Agent Space go to the **Web app** tab
2. Under **Operator access**, click **"Launch via IAM"**
3. This opens the Operator Web App — a separate UI where your ops team runs investigations, reviews RCA reports, and sees recommendations
4. Sessions via this link are limited to 8 hours

> For team access, configure **User access** on the same tab — choose either AWS IAM Identity Center or an external identity provider (Okta, Entra ID).

---

## Step 7: Inject a Fault (DevOps Agent Exercise)

Copy the broken app over the good one and redeploy:
```bash
cp fault/app-with-fault.js app/app.js
cd scripts && ./push-image.sh
```

The app will crash randomly. Within ~60 seconds you should see:
- CloudWatch log group `/ecs/hello-devops` receiving ERROR entries
- The `hello-devops-errors` alarm switching from `OK` to `ALARM`

Check alarm state:
```bash
aws cloudwatch describe-alarms \
  --alarm-names hello-devops-errors \
  --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
  --output table
```

Then in the **Operator Web App** for your Agent Space:

1. Click **New Investigation** (or wait — if the alarm is connected to the Agent Space it will auto-trigger)
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
