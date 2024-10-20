provider "aws" {
  region = "ap-southeast-2"
}

# Data source to fetch default VPC
data "aws_vpc" "default" {
  default = true
}

# Check if the IAM Role exists
data "aws_iam_role" "existing_role" {
  name = "EC2CloudWatchRole"
}

# IAM Role for EC2 instance
resource "aws_iam_role" "ec2_instance_role" {
  count = length(data.aws_iam_role.existing_role.id) > 0 ? 0 : 1

  name = "EC2CloudWatchRole"

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

# Attach CloudWatch policy to IAM Role
resource "aws_iam_role_policy_attachment" "attach_cw_logs_policy" {
  count = length(data.aws_iam_role.existing_role.id) > 0 ? 0 : 1

  role       = aws_iam_role.ec2_instance_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  count = length(data.aws_iam_role.existing_role.id) > 0 ? 0 : 1

  name = "EC2InstanceProfile"
  role = aws_iam_role.ec2_instance_role[0].name
}

# Security Group
resource "aws_security_group" "ec2_sg" {
  count = length(data.aws_security_group.existing_sg.*.id) > 0 ? 0 : 1

  name        = "allow_ssh_http"
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

# EC2 Instance
resource "aws_instance" "docker_ec2" {
  ami           = "ami-084e237ffb23f8f97"  # Amazon Linux 2 AMI
  instance_type = "t2.micro"
  key_name      = "personalawskey"  # Update with your EC2 Key Pair

  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile[0].name
  security_groups      = [aws_security_group.ec2_sg[0].name]

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo amazon-linux-extras install docker -y
    sudo service docker start
    sudo usermod -a -G docker ec2-user

    # Install CloudWatch Logs agent
    sudo yum install -y awslogs
    sudo systemctl start awslogsd
    sudo systemctl enable awslogsd.service

    # Create CloudWatch log group
    aws logs create-log-group --log-group-name /aws/docker/backend-logs --region ap-southeast-2 || true

    # Configure Docker logging to CloudWatch
    cat <<EOT > /etc/docker/daemon.json
    {
      "log-driver": "awslogs",
      "log-opts": {
        "awslogs-region": "ap-southeast-2",
        "awslogs-group": "/aws/docker/backend-logs",
        "awslogs-stream": "backend-container-logs",
        "awslogs-create-group": "true"
      }
    }
    EOT

    # Restart Docker service to apply changes
    sudo service docker restart

    # Clone your GitHub repository
    git clone https://github.com/agri-pass/agri-pass-backend.git /home/ec2-user/agri-pass-backend

    cd /home/ec2-user/agri-pass-backend
    # Build the Docker image
    docker build -t agri-pass-backend-image .

    # Run the Docker container
    docker run -d --name backend-container agri-pass-backend-image
  EOF

  tags = {
    Name = "DockerInstance"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "docker_log_group" {
  name              = "/aws/docker/backend-logs"
  retention_in_days = 7
}
