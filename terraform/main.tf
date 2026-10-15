data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------- Network ----------------
resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------- Security groups ----------------
resource "aws_security_group" "cicd" {
  name        = "${var.project}-cicd"
  description = "EC2 #1 - Jenkins and Docker"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Jenkins UI (admin) and GitHub webhooks"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = concat([var.admin_cidr], var.github_webhook_cidrs)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-cicd-sg" }
}

resource "aws_security_group" "app" {
  name        = "${var.project}-app"
  description = "EC2 #2 - k3s, app, Prometheus, Grafana"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description     = "SSH from Jenkins server (deployments)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.cicd.id]
  }

  ingress {
    description = "NodePorts: app dashboard (30080), Grafana (30030), Prometheus (30090)"
    from_port   = 30030
    to_port     = 30090
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-app-sg" }
}

# ---------------- EC2 #1: CI/CD server ----------------
resource "aws_instance" "cicd" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.cicd_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.cicd.id]
  key_name               = var.key_name
  user_data              = file("${path.module}/userdata-cicd.sh")

  credit_specification {
    cpu_credits = "standard" # never bill surplus CPU credits
  }

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = var.cicd_volume_gb
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${var.project}-cicd", Role = "cicd" }
}

# ---------------- EC2 #2: application & monitoring ----------------
resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = var.key_name
  user_data              = file("${path.module}/userdata-app.sh")

  credit_specification {
    cpu_credits = "standard" # never bill surplus CPU credits
  }

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = var.app_volume_gb
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${var.project}-app", Role = "app-monitoring" }
}
