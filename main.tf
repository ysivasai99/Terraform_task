provider "aws" {
  region = "ap-southeast-2"  # Use your AWS region
}

# IAM Role for CloudWatchFullAccess
resource "aws_iam_role" "ec2_cloudwatch_role" {
  name = "ec2_cloudwatch_role_unique"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach CloudWatchFullAccess Policy
resource "aws_iam_role_policy_attachment" "cloudwatch_full_access" {
  role       = aws_iam_role.ec2_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_instance_profile_nnewqq" {
  name = "ec2_instance_profile_nnewqq"
  role = aws_iam_role.ec2_cloudwatch_role.name
}

# Get the Default VPC
data "aws_vpc" "default" {
  default = true
}

# Get the Default Security Group with more specific constraints
data "aws_security_group" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "group-name"
    values = ["default"]  # Specify "default" to match the default security group
  }
}

# EC2 Instance using the default security group
resource "aws_instance" "ec2_instance" {
  ami                    = "ami-084e237ffb23f8f97"  # Use your AMI ID
  instance_type          = "t2.micro"
  key_name               = "personalawskey"
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile_nnewqq.name
  # Use the default security group
  vpc_security_group_ids = [data.aws_security_group.default.id]

  user_data = <<-EOF
  #!/bin/bash
  exec > /var/log/user-data.log 2>&1  # Log all output to this file

  # Update system packages
  echo "Updating system packages..."
  sudo yum update -y
  sudo yum install git -y
  ls -la ~/.ssh/
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  ssh-keygen -t rsa -b 2048 -C "ysivasai99@gmail.com"
  ls -la ~/.ssh/
  cat ~/.ssh/id_rsa.pub

  echo "PRIVATE_SSH_KEY_CONTENT" > /home/ec2-user/.ssh/id_rsa
  chmod 600 /home/ec2-user/.ssh/id_rsa
  chown -R ec2-user:ec2-user /home/ec2-user/.ssh

  # Add GitHub to known hosts to avoid prompt
  echo "Adding GitHub to known hosts..."
  ssh-keyscan github.com >> /home/ec2-user/.ssh/known_hosts

  # Clone private GitHub repository
  echo "Cloning repository..."
  git clone git@github.com:your-repo/agri-pass-backend.git /home/ec2-user/agri-pass-backend

  # Install Docker
  echo "Installing Docker..."
  sudo amazon-linux-extras install docker -y
  sudo service docker start
  sudo systemctl enable docker
  sudo usermod -a -G docker ec2-user

  # Build Docker image
  echo "Building Docker image..."
  cd /home/ec2-user/agri-pass-backend
  sudo docker build -t agri-pass-backend .

  # Run Docker container
  echo "Running Docker container..."
  sudo docker run -d --name agri-pass-backend-container agri-pass-backend

  # Install CloudWatch Agent
  echo "Installing CloudWatch Agent..."
  sudo yum install -y amazon-cloudwatch-agent

  # Create CloudWatch config file
  cat <<EOT >> /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
  {
    "logs": {
      "logs_collected": {
        "files": {
          "collect_list": [
            {
              "file_path": "/var/log/messages",
              "log_group_name": "ec2-instance-log-group",
              "log_stream_name": "{instance_id}-messages",
              "timestamp_format": "%b %d %H:%M:%S"
            },
            {
              "file_path": "/home/ec2-user/agri-pass-backend/logs/container.log",
              "log_group_name": "ec2-instance-log-group",
              "log_stream_name": "{instance_id}-container-log",
              "timestamp_format": "%b %d %H:%M:%S"
            }
          ]
        }
      }
    }
  }
  EOT

  # Start CloudWatch Agent
  sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a start -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

  EOF

  tags = {
    Name = "EC2-with-CloudWatch-Agent"
  }
}
