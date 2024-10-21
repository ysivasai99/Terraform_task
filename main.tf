provider "aws" {
  region = "ap-southeast-2"
}

locals {
  unique_suffix = format("%s-%s", timestamp(), random_id.unique_suffix.hex)
}

# Generate a random ID for unique naming
resource "random_id" "unique_suffix" {
  byte_length = 4
}

# Data source to fetch the default VPC
data "aws_vpc" "default" {
  default = true
}

# IAM Role for EC2 instance to allow logging to CloudWatch
resource "aws_iam_role" "ec2_cloudwatch_logs_role" {
  name  = "EC2-CloudWatch-Logs-Role2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Attach CloudWatch Logs Policy to IAM Role
resource "aws_iam_role_policy_attachment" "cloudwatch_logs_attachment" {
  role       = aws_iam_role.ec2_cloudwatch_logs_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_cloudwatch_logs_profile" {
  name = "EC2-CloudWatch-Logs-Instance-Profile-${local.unique_suffix}"
  role = aws_iam_role.ec2_cloudwatch_logs_role.name
}

# Security Group for EC2
resource "aws_security_group" "ec2_security_group" {
  name        = "SG-EC2-Docker-Logging-${local.unique_suffix}"
  description = "Allow SSH and HTTP inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# CloudWatch Log Group for EC2 instance logs
resource "aws_cloudwatch_log_group" "ec2_logs_group" {
  name              = "/aws/ec2/instance-logs"
  retention_in_days = 7
}

# CloudWatch Log Group for Docker container logs
resource "aws_cloudwatch_log_group" "docker_logs_group" {
  name              = "/aws/docker/container-logs"
  retention_in_days = 7
}

# CloudWatch Log Stream for EC2 logs
resource "aws_cloudwatch_log_stream" "ec2_log_stream" {
  name           = "ec2-instance-log-stream"
  log_group_name = aws_cloudwatch_log_group.ec2_logs_group.name
}

# CloudWatch Log Stream for Docker logs
resource "aws_cloudwatch_log_stream" "docker_log_stream" {
  name           = "docker-container-log-stream"
  log_group_name = aws_cloudwatch_log_group.docker_logs_group.name
}

# EC2 Instance with Docker installed, Git installation, and logging configured
resource "aws_instance" "docker_ec2_instance" {
  ami                    = "ami-084e237ffb23f8f97"  # Amazon Linux 2 AMI
  instance_type          = "t2.micro"
  key_name               = "personalawskey"  # Replace with your EC2 key pair

  iam_instance_profile   = aws_iam_instance_profile.ec2_cloudwatch_logs_profile.name
  security_groups        = [aws_security_group.ec2_security_group.name]

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y

    # Install Docker
    sudo amazon-linux-extras install docker -y
    sudo service docker start
    sudo usermod -a -G docker ec2-user

    # Install and configure CloudWatch Logs agent
    sudo yum install -y awslogs
    sudo systemctl start awslogsd
    sudo systemctl enable awslogsd.service

    # Configure CloudWatch Logs for EC2
    cat <<EOT > /etc/awslogs/awslogs.conf
    [general]
    state_file = /var/lib/awslogs/agent-state

    [/var/log/messages]
    file = /var/log/messages
    log_group_name = ${aws_cloudwatch_log_group.ec2_logs_group.name}
    log_stream_name = ${aws_cloudwatch_log_stream.ec2_log_stream.name}
    datetime_format = %b %d %H:%M:%S

    [/var/log/cloud-init.log]
    file = /var/log/cloud-init.log
    log_group_name = ${aws_cloudwatch_log_group.ec2_logs_group.name}
    log_stream_name = ${aws_cloudwatch_log_stream.ec2_log_stream.name}
    datetime_format = %b %d %H:%M:%S
    EOT

    sudo systemctl restart awslogsd

    # Install Git
    sudo yum install -y git

    # Clone Git repository (replace the URL with your repository)
    git clone https://github.com/your-username/your-repository.git /home/ec2-user/your-repository

    # Navigate to the repository directory
    cd /home/ec2-user/your-repository

    # Pull your Docker image (replace with your actual image)
    docker pull your-docker-image

    # Run Docker container with awslogs log driver for CloudWatch
    docker run -d \
      --log-driver=awslogs \
      --log-opt awslogs-region=ap-southeast-2 \
      --log-opt awslogs-group=${aws_cloudwatch_log_group.docker_logs_group.name} \
      --log-opt awslogs-stream=${aws_cloudwatch_log_stream.docker_log_stream.name} \
      your-docker-image
  EOF

  tags = {
    Name = "Docker-EC2-Instance"
  }
}

# Output the instance ID and public IP for reference
output "instance_id" {
  value = aws_instance.docker_ec2_instance.id
}

output "instance_public_ip" {
  value = aws_instance.docker_ec2_instance.public_ip
}
