# Infracost Proof of Concept (POC)

Automated cloud cost estimation, FinOps guardrails, and pull request diffs for Terraform using **Infracost CLI v2** and **GitHub Actions**.

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [1. Install Infracost CLI](#1-install-infracost-cli)
- [2. Authenticate & Generate CLI v2 Token](#2-authenticate--generate-cli-v2-token)
- [3. Configure GitHub Repository Secrets](#3-configure-github-repository-secrets)
- [4. Set Up GitHub Actions Workflows](#4-set-up-github-actions-workflows)
  - [Crucial Fix: `infracost-scanner` vs `infracost-ci`](#crucial-fix-infracost-scanner-vs-infracost-ci)
- [5. Define Sample Infrastructure (`main.tf`)](#5-define-sample-infrastructure-maintf)
- [6. Test Locally](#6-test-locally)
- [7. Test in a GitHub Pull Request](#7-test-in-a-github-pull-request)
- [8. Understanding PR Comments & FinOps Guardrails](#8-understanding-pr-comments--finops-guardrails)

---

## Overview

This repository demonstrates shift-left FinOps:
- **Cost Diff on Pull Requests:** Automatically calculates monthly cost changes introduced by Terraform code changes and posts a breakdown comment on the PR.
- **Baseline Cost Tracking:** Automatically tracks default branch costs upon merge.
- **FinOps Policies & Guardrails:** Catches over-budget items, unattached resources, non-Graviton instances, and policy violations directly in CI before merging.

---

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) (>= 1.0.0)
- [Git](https://git-scm.com/)
- An [Infracost Cloud account](https://dashboard.infracost.io/) (free tier available)
- A GitHub repository with GitHub Actions enabled

---

## 1. Install Infracost CLI

Install the Infracost CLI locally:

### macOS (Homebrew)
```bash
brew install infracost
```

### Linux
```bash
curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh
```

### Windows
```powershell
choco install infracost
# or
scoop install infracost
```

Verify your installation:
```bash
infracost --version
# Expected: infracost version v2.x.x
```

---

## 2. Authenticate & Generate CLI v2 Token

### Step A: Interactive Login
Run the interactive login command:
```bash
infracost auth login
```
This opens your browser. Follow the prompts to authenticate with your Infracost Cloud account. Once logged in, verify your active organization:
```bash
infracost auth whoami
```

### Step B: Generate a Persistent CLI v2 Token for CI/CD
Interactive logins use temporary OAuth tokens which expire. For CI/CD pipelines, generate a persistent **CLI v2 Token**:

1. Log in to **[dashboard.infracost.io](https://dashboard.infracost.io)**.
2. Go to **Org Settings** (bottom-left or top-left) → **Automation** → **CLI tokens** (or visit [dashboard.infracost.io/org/settings](https://dashboard.infracost.io/org/settings)).
3. Under the **CLI v2 tokens** section, click **`+ Create CLI v2 tokens`**.
4. Enter a name (e.g. `github-actions-ci`) and choose an expiration period.
5. **Copy the generated token**.

> [!NOTE]
> Do not use tokens from the **API tokens** menu in the left sidebar—those are reserved for programmatic Infracost Cloud Management API / GraphQL access, not CI/CD pipeline scans.

---

## 3. Configure GitHub Repository Secrets

Add the token to your GitHub repository so GitHub Actions can authenticate with Infracost:

1. Open your repository on GitHub.
2. Navigate to **Settings** → **Secrets and variables** → **Actions**.
3. Under **Repository secrets**, click **New repository secret**.
4. Set:
   - **Name:** `INFRACOST_API_KEY`
   - **Secret:** *(Paste your CLI v2 token)*
5. Click **Add secret**.

> [!IMPORTANT]
> Make sure the secret is added under **Repository secrets**, not **Environment secrets**, so all jobs can access it.

---

## 4. Set Up GitHub Actions Workflows

Two workflow files manage the CI lifecycle:

1. [`.github/workflows/infracost-diff.yml`](.github/workflows/infracost-diff.yml): Runs on pull requests, compares head branch against base branch, and posts the cost comment.
2. [`.github/workflows/infracost-scan.yml`](.github/workflows/infracost-scan.yml): Runs on pushes to `master`/`main` to upload baseline cost data to the dashboard.

### Crucial Fix: `infracost-scanner` vs `infracost-ci`

When using the `ghcr.io/infracost/ci:0.1` container, the binary inside the container is named **`infracost-scanner`** (not `infracost-ci`). 

Ensure your workflow run steps call `infracost-scanner`:

```yaml
# In .github/workflows/infracost-scan.yml
- name: Run Infracost Scan
  env:
    INFRACOST_CLI_AUTHENTICATION_TOKEN: ${{ secrets.INFRACOST_API_KEY }}
  run: infracost-scanner scan --path .
```

```yaml
# In .github/workflows/infracost-diff.yml
- name: Run Infracost Diff
  if: github.event.action != 'closed'
  env:
    INFRACOST_CLI_AUTHENTICATION_TOKEN: ${{ secrets.INFRACOST_API_KEY }}
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    INFRACOST_VCS_PULL_REQUEST_ID: ${{ needs.infracost-pr.outputs.pr-number }}
  run: infracost-scanner diff --base-path base --head-path head

- name: Update pull request status
  if: github.event.action == 'closed'
  env:
    INFRACOST_CLI_AUTHENTICATION_TOKEN: ${{ secrets.INFRACOST_API_KEY }}
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    INFRACOST_VCS_PULL_REQUEST_ID: ${{ needs.infracost-pr.outputs.pr-number }}
    PR_STATUS: ${{ github.event.pull_request.merged && 'MERGED' || 'CLOSED' }}
  run: infracost-scanner status --status "$PR_STATUS"
```

---

## 5. Define Sample Infrastructure (`main.tf`)

Create [`main.tf`](main.tf) with sample AWS resources:

```hcl
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  # Infracost prices IaC statically; real AWS credentials are not required
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

resource "aws_instance" "web_app" {
  ami           = "ami-0c7217cdde317cfec" # Amazon Linux 2023
  instance_type = "m5.large"

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name        = "web-server"
    Environment = "production"
  }
}
```

---

## 6. Test Locally

Run a scan against your current directory to verify pricing:

```bash
infracost scan .
```

Example output:
```text
╭──────────────────────────────────────────────────────────────────────────────╮
│                                                                              │
│   Scan Summary                                                               │
│                                                                              │
│   Resources:     1 (1 costed, 0 free)                                        │
│   Monthly cost:  $74                                                         │
│                                                                              │
│   FinOps:        5 (⚠️ x2)                                                   │
│   Tagging:       1 (⚠️ x1)                                                   │
│   Guardrails:    0                                                           │
│   Budgets:       0                                                           │
│                                                                              │
│   ⚠️  = failing policy                                                       │
│                                                                              │
╰──────────────────────────────────────────────────────────────────────────────╯
```

Inspect failing policies:
```bash
infracost inspect --failing
```

---

## 7. Test in a GitHub Pull Request

1. **Create and switch to a feature branch:**
   ```bash
   git checkout -b test
   ```

2. **Commit and push your changes:**
   ```bash
   git add .
   git commit -m "feat: add EC2 web instance"
   git push -u origin test
   ```

3. **Open a Pull Request:**
   - Go to your repository on GitHub.
   - Click **Compare & pull request** (`test` → `master`).
   - Submit the PR.

4. **Observe GitHub Actions:**
   - The `Infracost Diff` workflow triggers automatically.
   - Within 1–2 minutes, Infracost will post an automated comment detailing the monthly cost difference (`+$74.00/mo`).

---

## 8. Understanding PR Comments & FinOps Guardrails

Infracost checks both cost diffs and organizational FinOps/security policies.

### Example Policy Failures
If your PR CI check shows a failure like:
```text
Blocking: policy "EC2 - consider using Graviton instances" has failing resources
Blocking: policy "[EC2.9, EC2.25] Amazon EC2 and launch templates should not associate a public IPv4 address" has failing resources
```

- **Policy: Graviton Instances**
  - *Reason:* `m5.large` uses x86 Intel CPUs.
  - *FinOps Benefit:* Switching to Graviton (e.g. `m6g.large` with an ARM AMI) can save up to ~20% in monthly compute costs.
- **Policy: Public IPv4 Association**
  - *Reason:* Instances in default subnets may assign a public IPv4 address.
  - *Cost & Security:* AWS charges ~$3.65/month ($0.005/hr) per public IPv4, and instances should generally sit behind load balancers.

### Resolving Policies in Code
Update `main.tf` to satisfy both recommendations:

```hcl
resource "aws_instance" "web_app" {
  ami                         = "ami-0c7217cdde317cfec" # Update to ARM64 AMI for Graviton
  instance_type               = "m6g.large"            # Graviton instance type
  associate_public_ip_address = false                  # Disable public IPv4

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name        = "web-server"
    Environment = "production"
  }
}
```

Commit and push the update to your branch:
```bash
git add main.tf
git commit -m "fix(finops): use graviton instance and remove public ipv4"
git push
```
The Infracost workflow will re-run automatically, update the cost diff comment, and clear the policy blockers.
