terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # You can change this to your preferred region
}

resource "aws_instance" "monitoring_server" {
  ami           = "ami-053b0d53c279acc90" # Ubuntu 22.04 LTS
  instance_type = "t3.2xlarge"

  root_block_device {
    volume_size = 50 # in GB
    volume_type = "gp3"
  }

  key_name      = "otel-dep-key"    # Make sure to replace this with your key pair name

  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              set -e

              # Function to check if a command exists
              command_exists() {
                  command -v "$1" >/dev/null 2>&1
              }

              # Update and install dependencies
              sudo apt-get update -y
              sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

              # Install Docker if not already installed
              if ! command_exists docker; then
                  echo "Installing Docker..."
                  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
                  sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
                  sudo apt-get update -y
                  sudo apt-get install -y docker-ce
                  sudo usermod -aG docker ubuntu
              else
                  echo "Docker is already installed."
              fi

              # Install Minikube if not already installed
              if ! command_exists minikube; then
                  echo "Installing Minikube..."
                  curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
                  chmod +x minikube
                  sudo mv minikube /usr/local/bin/
              else
                  echo "Minikube is already installed."
              fi

              # Install kubectl if not already installed
              if ! command_exists kubectl; then
                  echo "Installing kubectl..."
                  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                  chmod +x kubectl
                  sudo mv kubectl /usr/local/bin/
              else
                  echo "kubectl is already installed."
              fi

              # Install Helm if not already installed
              if ! command_exists helm; then
                  echo "Installing Helm..."
                  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
              else
                  echo "Helm is already installed."
              fi

              # Start Minikube if not already running
              if ! sudo -u ubuntu minikube status | grep -q "Running"; then
                  echo "Starting Minikube..."
                  sudo -u ubuntu minikube start --driver=docker --cpus=6 --memory=12288m
              else
                  echo "Minikube is already running."
              fi

              # Wait for Kubernetes API to be ready
              until sudo -u ubuntu /usr/local/bin/minikube kubectl -- get nodes; do echo "Waiting for Kubernetes API..."; sleep 10; done

              # Install Helm charts if not already installed
              install_helm_chart() {
                  local release_name=$1
                  local chart_name=$2
                  local namespace=$3
                  local extra_args=$4

                  if ! sudo -u ubuntu helm status -n "$namespace" "$release_name" > /dev/null 2>&1; then
                      echo "Installing $release_name..."
                      sudo -u ubuntu helm install "$release_name" "$chart_name" --namespace "$namespace" --create-namespace --wait $extra_args
                  else
                      echo "$release_name is already installed."
                  fi
              }

              sudo -u ubuntu helm repo add jetstack https://charts.jetstack.io
              sudo -u ubuntu helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
              sudo -u ubuntu helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
              sudo -u ubuntu helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
              sudo -u ubuntu helm repo update

              install_helm_chart cert-manager jetstack/cert-manager cert-manager "--set installCRDs=true"
              install_helm_chart sealed-secrets sealed-secrets/sealed-secrets kube-system "--version 1.16.1"
              install_helm_chart opentelemetry-operator open-telemetry/opentelemetry-operator default
              install_helm_chart prometheus prometheus-community/kube-prometheus-stack monitoring "--set prometheus.prometheusSpec.resources.limits.cpu=1 --set prometheus.prometheusSpec.resources.limits.memory=2Gi"

              # Install Jaeger Operator if not already installed
              if ! sudo -u ubuntu /usr/local/bin/minikube kubectl -- get deployment jaeger-operator -n observability > /dev/null 2>&1; then
                  echo "Installing Jaeger Operator..."
                  sudo -u ubuntu /usr/local/bin/minikube kubectl -- create namespace observability
                  sudo -u ubuntu /usr/local/bin/minikube kubectl -- apply -f https://github.com/jaegertracing/jaeger-operator/releases/latest/download/jaeger-operator.yaml -n observability
              else
                  echo "Jaeger Operator is already installed."
              fi

              # Move .kube and .minikube to ubuntu user's home if not already there
              if [ ! -d /home/ubuntu/.kube ]; then
                  sudo mv /root/.kube /home/ubuntu/
                  sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube
              fi
              if [ ! -d /home/ubuntu/.minikube ]; then
                  sudo mv /root/.minikube /home/ubuntu/
                  sudo chown -R ubuntu:ubuntu /home/ubuntu/.minikube
              fi

              # Apply Kubernetes manifests
              sudo -u ubuntu /usr/local/bin/minikube kubectl -- apply -f /home/ubuntu/otel-collector.yaml
              sudo -u ubuntu /usr/local/bin/minikube kubectl -- apply -f /home/ubuntu/otel-app-dep.yaml
              sudo -u ubuntu /usr/local/bin/minikube kubectl -- apply -f /home/ubuntu/otel-app-svc.yaml
              sudo -u ubuntu /usr/local/bin/minikube kubectl -- apply -f /home/ubuntu/otel-servicemonitor.yaml
              sudo -u ubuntu /usr/local/bin/minikube kubectl -- apply -f /home/ubuntu/jaeger.yaml -n observability
              
              EOF

  provisioner "file" {
    source      = "kubernetes/otel-collector.yaml"
    destination = "/home/ubuntu/otel-collector.yaml"
  }

  provisioner "file" {
    source      = "kubernetes/otel-app-dep.yaml"
    destination = "/home/ubuntu/otel-app-dep.yaml"
  }

  provisioner "file" {
    source      = "kubernetes/otel-app-svc.yaml"
    destination = "/home/ubuntu/otel-app-svc.yaml"
  }

  provisioner "file" {
    source      = "kubernetes/jaeger.yaml"
    destination = "/home/ubuntu/jaeger.yaml"
  }

  provisioner "file" {
    source      = "kubernetes/otel-servicemonitor.yaml"
    destination = "/home/ubuntu/otel-servicemonitor.yaml"
  }

  provisioner "file" {
    source      = "../scheduling-validator-agent/get-sealed-secrets-public-key.sh"
    destination = "/home/ubuntu/get-sealed-secrets-public-key.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/get-sealed-secrets-public-key.sh"
    ]
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("/Users/edwardhanks/Cline/.ssh/otel-dep-key.pem") # IMPORTANT: Make sure this path is correct
    host        = self.public_ip
  }

  tags = {
    Name = "Monitoring-Server"
  }
}


resource "aws_security_group" "monitoring_sg" {
  name        = "monitoring-sg"
  description = "Allow all necessary ports for monitoring stack"
}

resource "aws_security_group_rule" "allow_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.monitoring_sg.id
}

data "http" "my_ip" {
  url = "http://checkip.amazonaws.com"
}

resource "aws_security_group_rule" "allow_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["${chomp(data.http.my_ip.response_body)}/32"]
  security_group_id = aws_security_group.monitoring_sg.id
}

resource "aws_security_group_rule" "allow_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring_sg.id
}

resource "aws_security_group_rule" "allow_grafana" {
  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring_sg.id
}

resource "aws_security_group_rule" "allow_prometheus" {
  type              = "ingress"
  from_port         = 9091
  to_port           = 9091
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring_sg.id
}

resource "aws_security_group_rule" "allow_jaeger" {
  type              = "ingress"
  from_port         = 16686
  to_port           = 16686
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring_sg.id
}

resource "aws_security_group_rule" "allow_sample_app" {
  type              = "ingress"
  from_port         = 30080
  to_port           = 30080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring_sg.id
}

resource "aws_security_group_rule" "allow_all_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring_sg.id
}

output "monitoring_server_private_ip" {
  value = aws_instance.monitoring_server.private_ip
}

output "monitoring_sg_id" {
  value = aws_security_group.monitoring_sg.id
}
