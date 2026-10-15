# Cloud-Native DevOps Monitoring and CI/CD Platform

An automated CI/CD and monitoring platform that deploys a Node.js application to AWS using Jenkins, Docker, and k3s. Prometheus collects application and infrastructure metrics, while Grafana provides a centralized monitoring dashboard.

## Architecture

**Workflow:** GitHub → Jenkins → Tests → Docker Build → Docker Hub → k3s Deployment → Prometheus → Grafana

The infrastructure runs on two AWS EC2 instances provisioned using Terraform.

| Component | EC2 #1: CI/CD Server | EC2 #2: Application & Monitoring |
|---|---|---|
| Operating system | Ubuntu | Ubuntu |
| Main services | Jenkins, Docker | k3s, Node.js, Prometheus, Grafana, Node Exporter |
| Instance type | `t3.micro` (Terraform default) | `t3.small` (deployed configuration) |
| Purpose | Build, test, and publish application images | Run the application and collect monitoring metrics |

## Technologies Used

- **AWS EC2:** Hosts the CI/CD server, application, and monitoring services.
- **Terraform:** Provisions cloud infrastructure and security groups.
- **Jenkins:** Automates the CI/CD pipeline.
- **Docker:** Builds and packages the application into a container image.
- **Docker Hub:** Stores application images.
- **k3s:** Runs and manages the containerized application.
- **Prometheus:** Collects application and infrastructure metrics.
- **Grafana:** Displays metrics through monitoring dashboards.
- **Node.js and Express:** Provide the application and its HTTP endpoints.
- **GitHub:** Stores the source code and triggers pipeline execution through webhooks.

## Project Structure

```text
.
├── terraform/    # Infrastructure provisioning and bootstrap scripts
├── Jenkinsfile   # Automated CI/CD pipeline
├── app/          # Node.js application, tests, metrics and Dockerfile
├── k8s/          # Kubernetes manifests and monitoring configuration
└── scripts/      # Deployment automation scripts
```

## CI/CD Pipeline

When changes are pushed to the configured GitHub repository, the webhook triggers Jenkins.

The pipeline performs the following steps:

1. Checks out the application source code.
2. Installs dependencies and runs automated tests.
3. Builds a Docker image.
4. Pushes the image to Docker Hub.
5. Connects to the application server and deploys the new image to k3s.
6. Checks the Kubernetes rollout status to verify deployment.

This workflow reduces manual deployment steps and makes application updates more consistent.

## Monitoring and Observability

Prometheus collects metrics from the application and configured infrastructure targets. Grafana presents these metrics in a centralized dashboard.

The monitoring setup includes:

- Application health and Prometheus target status.
- HTTP request activity.
- Node.js process memory and event-loop metrics.
- EC2 CPU utilization and memory usage.
- Disk utilization and network traffic.
- Prometheus scrape duration.

Node Exporter provides host-level metrics used for infrastructure monitoring.

### Accessing the Services

Replace the example addresses with the current public IP addresses of your EC2 instances.

| Service | URL |
|---|---|
| Deployed application | `http://<app-public-ip>:30080` |
| Grafana monitoring dashboard | `http://<app-public-ip>:30030` |
| Prometheus | `http://<app-public-ip>:30090` |
| Jenkins | `http://<jenkins-public-ip>:8080` |

Grafana dashboard: **CICD DevOps Monitoring**

The services are exposed through configured ports. Access should be restricted through AWS security groups, and administrative services should not be exposed publicly without appropriate security controls.

## Running the Application Locally

Requirements: Node.js and npm.

```bash
cd app
npm ci
npm test
npm start
```

The application runs on port `3000` by default.

Available endpoints include:

- `/healthz` — application health check.
- `/metrics` — Prometheus metrics.
- `/api/hello` — application endpoint used for testing.

## Infrastructure Provisioning

Requirements:

- AWS account and configured AWS CLI credentials.
- Terraform 1.5 or later.
- An existing EC2 key pair in the selected AWS region.
- Docker Hub account and access token.
- A GitHub repository containing the project.

Example commands:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Configure the variables in `terraform.tfvars` before applying the infrastructure. Use your own key pair and restrict administrative access to your IP address.

After provisioning, use the Terraform outputs to retrieve the instance addresses and service URLs.

**Note:** Terraform defaults and the currently deployed infrastructure may differ. Verify the configured instance types, IP addresses, and security groups before applying changes to existing resources.

## Testing the Deployment

Verify the Kubernetes workloads on the application server:

```bash
kubectl get pods -n devops
kubectl get deployments,services -n devops
```

Check the application health endpoint:

```bash
curl http://localhost:3000/healthz
```

Verify the Prometheus targets in the Prometheus web interface and confirm that the Grafana panels display current metrics.

For the CI/CD workflow, push a small application change and verify that Jenkins runs the pipeline and the updated version is deployed successfully.

## Known Limitations

- The application and monitoring workloads share a single application EC2 instance, so available CPU and memory are limited.
- The k3s cluster runs on a single node and does not provide high availability across multiple nodes or availability zones.
- Kubernetes rollouts may temporarily require resources for more than one application pod.
- Public IP addresses may change when EC2 instances are stopped and started.
- The service URLs use HTTP rather than HTTPS.
- Alertmanager-based alerting is not configured.
- The monitoring dashboard provides application and infrastructure metrics; live Jenkins pipeline status and deployment history are not integrated into the dashboard.

## Security Considerations

- Do not commit private keys, AWS credentials, Docker Hub tokens, or other secrets.
- Store deployment credentials in Jenkins Credentials.
- Restrict SSH, Jenkins, Grafana, and Prometheus access through appropriate security groups.
- Change default Grafana credentials and use appropriate authentication.
- Use HTTPS and stronger access controls before exposing the platform beyond a controlled demonstration environment.

## Cleanup

When the infrastructure is no longer needed, review the Terraform plan and destroy the resources created by this project:

```bash
cd terraform
terraform destroy
```

Check AWS resources and billing after cleanup to ensure that no unnecessary resources remain.

## Project Outcome

The project demonstrates an automated deployment workflow combined with application and infrastructure monitoring. It brings together source control, automated testing, containerization, cloud infrastructure, Kubernetes deployment, metrics collection, and dashboard visualization in one platform.
