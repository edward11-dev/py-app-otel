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
              sudo apt-get update -y
              sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
              # Install Docker
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
              sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
              sudo apt-get update -y
              sudo apt-get install -y docker-ce
              sudo usermod -aG docker ubuntu

              # Install Minikube
              curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
              chmod +x minikube
              sudo mv minikube /usr/local/bin/

              # Install kubectl
              curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
              chmod +x kubectl
              sudo mv kubectl /usr/local/bin/

              # Install Helm
              curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

              # Start Minikube as ubuntu user
              sudo -u ubuntu minikube start --driver=docker --cpus=6 --memory=12288m

              # Wait for Kubernetes API to be ready
              until sudo -u ubuntu /usr/local/bin/minikube kubectl -- get nodes; do echo "Waiting for Kubernetes API..."; sleep 10; done

              # Install cert-manager as ubuntu user
              sudo -u ubuntu helm repo add jetstack https://charts.jetstack.io
              sudo -u ubuntu helm repo update
              sudo -u ubuntu helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set installCRDs=true --wait

              # Install Sealed Secrets Controller as ubuntu user
              sudo -u ubuntu helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
              sudo -u ubuntu helm repo update
              sudo -u ubuntu helm install sealed-secrets sealed-secrets/sealed-secrets --namespace kube-system --wait

              # Install OpenTelemetry Operator as ubuntu user
              sudo -u ubuntu helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
              sudo -u ubuntu helm repo update
              sudo -u ubuntu helm install opentelemetry-operator open-telemetry/opentelemetry-operator --wait

              # Install Prometheus and Grafana using Helm as ubuntu user
              sudo -u ubuntu helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
              sudo -u ubuntu helm repo update
              sudo -u ubuntu helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace --wait \
                --set prometheus.prometheusSpec.resources.limits.cpu=1 \
                --set prometheus.prometheusSpec.resources.limits.memory=2Gi

              # Install Jaeger as ubuntu user
              sudo -u ubuntu /usr/local/bin/minikube kubectl -- create namespace observability
              sudo -u ubuntu /usr/local/bin/minikube kubectl -- apply -f https://github.com/jaegertracing/jaeger-operator/releases/latest/download/jaeger-operator.yaml -n observability
              sudo -u ubuntu /usr/local/bin/minikube kubectl -- apply -f /home/ubuntu/jaeger.yaml -n observability

              # Move .kube and .minikube to ubuntu user's home
              sudo mv /root/.kube /root/.minikube /home/ubuntu/
              sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube /home/ubuntu/.minikube

              # Apply Kubernetes manifests
              sudo -u ubuntu /usr/local/bin/minikube kubectl -- apply -f /home/ubuntu/otel-collector.yaml
              sudo -u ubuntu /usr/local/bin/minikube kubectl -- apply -f /home/ubuntu/otel-app-dep.yaml
              sudo -u ubuntu /usr/local/bin/minikube kubectl -- apply -f /home/ubuntu/otel-app-svc.yaml
              sudo -u ubuntu /usr/local/bin/minikube kubectl -- apply -f /home/ubuntu/otel-servicemonitor.yaml
              
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

resource "aws_instance" "github_runner" {
  ami           = "ami-053b0d53c279acc90" # Ubuntu 22.04 LTS
  instance_type = "t2.micro"

  key_name      = "otel-dep-key" # Make sure to replace this with your key pair name
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install -y curl jq

              # Create a directory for the runner
              mkdir /home/ubuntu/actions-runner && cd /home/ubuntu/actions-runner
              # Download the latest runner package
              curl -o actions-runner-linux-x64-2.309.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.309.0/actions-runner-linux-x64-2.309.0.tar.gz
              # Extract the installer
              tar xzf ./actions-runner-linux-x64-2.309.0.tar.gz
              # Change ownership to ubuntu user
              sudo chown -R ubuntu:ubuntu /home/ubuntu/actions-runner
              EOF

  tags = {
    Name = "GitHub-Runner"
  }

  provisioner "file" {
    source      = "../scheduling-validator-agent/configure-runner.sh"
    destination = "/home/ubuntu/configure-runner.sh"
  }

  # Make the script executable
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/configure-runner.sh"
    ]
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("/Users/edwardhanks/Cline/.ssh/otel-dep-key.pem")
    host        = self.public_ip
  }
}

resource "aws_security_group" "monitoring_sg" {
  name        = "monitoring-sg"
  description = "Allow all necessary ports for monitoring stack"

  # Allow all internal traffic within the security group
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }
}

resource "aws_security_group_rule" "allow_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
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

output "github_runner_public_ip" {
  value = aws_instance.github_runner.public_ip
}
