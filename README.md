# Cloud-Native DevOps Monitoring and CI/CD Platform

GitHub push → Jenkins → test → Docker build → Docker Hub → k3s deployment → Prometheus → Grafana → custom dashboard,
running on **two AWS EC2 instances** provisioned by Terraform.

| | EC2 #1 — CI/CD server | EC2 #2 — App & monitoring |
|---|---|---|
| Runs | Ubuntu, Jenkins, Docker | Ubuntu, k3s, Node.js app, Prometheus, Grafana |
| Size (default) | `t3.micro` (1 GB RAM) | `t3.small` (2 GB RAM) |
| Ports (restricted to your IP) | 22, 8080 (Jenkins) | 22, 30080 (dashboard), 30030 (Grafana), 30090 (Prometheus) |

```
.
├── terraform/      VPC, subnet, security groups, 2 x EC2 (+ bootstrap scripts)
├── Jenkinsfile     CI/CD pipeline
├── app/            Node.js + Express app, /metrics, custom dashboard, tests, Dockerfile
├── k8s/            Namespace, app, Prometheus (+RBAC), Grafana, provisioned dashboard
└── scripts/        deploy.sh (runs on EC2 #2 during the Deploy stage)
```

## Before you start

- AWS account + CLI credentials configured (`aws configure`), Terraform >= 1.5
- An existing **EC2 key pair** in your chosen region (default `ap-south-1`)
- A **Docker Hub** account and an access token (Account Settings → Security)
- This repo pushed to your own GitHub repository
- **Free tier:** see the "Running on the free tier" section below before you `apply`.

## Running on the free tier (t3.micro)

The defaults are `t3.micro` x2, 15 GB disks, `standard` CPU credits (so burst usage is never billed as surplus), and the stack is tuned for 1 GB of RAM (2 GB swap on each instance, Jenkins heap capped at 384 MB, 1 app replica, small Prometheus/Grafana limits, k3s without Traefik/servicelb/metrics-server).

How "free" works depends on when your AWS account was created (check Billing → Free Tier, and confirm the instance type shows "Free tier eligible" in your region):

- **Account created before 15 July 2025:** 750 EC2 hours/month **shared across all instances**, for 12 months. Two instances running 24/7 use ~1,460 hours, so run them for roughly half the month, or **stop them when idle**. Public IPv4 addresses have their own allowance, so check the dashboard.
- **Account created on/after 15 July 2025 (Free plan):** usage draws down your $100–$200 of credits for up to 6 months; a `t3.micro` is about $0.01/hour. Two instances 24/7 use a small fraction of the credits, but they run out eventually.

Stop (don't terminate) when idle: `aws ec2 stop-instances --instance-ids <ids>`. Disks are kept; **public IPs change on restart**, so update the webhook URL and `APP_HOST`.

**Expect it to be slow.** EC2 #1 (Jenkins) should work, with builds taking a few minutes. EC2 #2 is the tight one: k3s alone uses roughly half the RAM, and swap on EBS is slow. If pods get `OOMKilled` or SSH becomes unresponsive, check with `free -m` and `sudo k3s kubectl -n devops get pods`, then set `app_instance_type = "t3.small"` in `terraform.tfvars` (about double the hourly price, and free-tier eligible on new-plan accounts) and `terraform apply`.

## 1. Provision infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set admin_cidr (your IP/32) and key_name
terraform init
terraform plan
terraform apply
```

Note the outputs (`jenkins_url`, `app_private_ip`, `dashboard_url`, ...). Bootstrap scripts take a few minutes after the instances show as running.
Public IPs change if you stop/start an instance; re-run `terraform output` and update the webhook URL.

## 2. Configure Jenkins (one-time)

1. `ssh -i <key>.pem ubuntu@<cicd_public_ip>` then `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`
2. Open `jenkins_url`, unlock, install the suggested plugins **plus**: *SSH Agent*, *GitHub*.
3. **Manage Jenkins → Credentials → add:**
   - `dockerhub` — *Username with password*: Docker Hub username + access token
   - `app-server-ssh` — *SSH Username with private key*: username `ubuntu`, the private key of your EC2 key pair
4. Edit the two placeholders in `Jenkinsfile` (`DOCKERHUB_USER`, `APP_HOST` = `terraform output app_private_ip`), commit and push.
5. **New Item → Pipeline → Pipeline script from SCM** → your GitHub repo URL, branch `main`, script path `Jenkinsfile`. Run **Build Now** once so Jenkins registers the trigger.

## 3. Connect GitHub → Jenkins

GitHub repo → Settings → Webhooks → Payload URL `http://<cicd_public_ip>:8080/github-webhook/`, content type `application/json`, "Just the push event".

Jenkins' port is restricted to your IP by default, so GitHub cannot reach it until you allow GitHub's webhook ranges:

```bash
curl -s https://api.github.com/meta | python3 -c "import json,sys; print(json.dumps([c for c in json.load(sys.stdin)['hooks'] if ':' not in c]))"
```

Put that list into `github_webhook_cidrs` in `terraform.tfvars` and `terraform apply` again. (GitHub's ranges change occasionally. If you would rather not open the port, replace `githubPush()` in the Jenkinsfile with `pollSCM('H/2 * * * *')`.)

## 4. Use it

Push a change to `app/`. Jenkins checks out, installs, tests, builds, pushes `<user>/devops-app:<build>-<sha>`, then deploys to k3s and waits for the rollout. A failed rollout is rolled back automatically.

| What | URL |
|---|---|
| Custom monitoring dashboard | `http://<app_public_ip>:30080` |
| Grafana (login `admin` / `admin`, **change on first login**) | `http://<app_public_ip>:30030` — dashboard *DevOps → DevOps Platform - Application Overview* |
| Prometheus | `http://<app_public_ip>:30090` |

Generate some traffic to see the graphs move:
```bash
for i in $(seq 1 200); do curl -s http://<app_public_ip>:30080/api/hello >/dev/null; curl -s http://<app_public_ip>:30080/api/fail >/dev/null; done
```

## Run the app locally

```bash
cd app && npm ci && npm test && npm start     # http://localhost:3000, /metrics, /healthz
```

## Teardown

```bash
cd terraform && terraform destroy
```

## Known limitations

- 1 GB instances are at their limit: no headroom for extra replicas, and rollouts briefly run two app pods at once.
- Single node k3s and single AZ: this demonstrates the workflow, it is not highly available.
- Prometheus collects **application-process** metrics (CPU, memory, event loop, HTTP). Host-level metrics (disk, network) would need `node_exporter`, which is not included.
- The dashboard shows the deployed version, commit and build number, but not live Jenkins pipeline status or deployment history; that would need the Jenkins API and credentials.
- HTTP only, no TLS; access is limited by security groups, not authentication. Do not widen `admin_cidr` to `0.0.0.0/0` (Terraform rejects it).
- Alerting (Alertmanager) is not configured.
