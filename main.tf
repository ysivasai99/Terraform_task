provider "aws" {
  region = "ap-southeast-2"
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Create a subnet in the VPC
resource "aws_subnet" "main" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-southeast-2a"
}

# Create a security group allowing SSH
resource "aws_security_group" "allow_ssh" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Replace with your IP in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}

# Create an IAM role for EC2 with CloudWatch permissions
resource "aws_iam_role" "ec2_role" {
  name = "ec2-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      },
    ]
  })
}

# Attach CloudWatchFullAccess policy to the IAM role
resource "aws_iam_role_policy_attachment" "cloudwatch_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
  role       = aws_iam_role.ec2_role.name
}

# Create an IAM instance profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# Create CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ec2_log_group" {
  name = "ec2-instance-log-group"
  retention_in_days = 14
}

# EC2 Instance with Docker, GitHub, and CloudWatch configuration
resource "aws_instance" "my_instance" {
  ami                    = "ami-084e237ffb23f8f97"   # Amazon Linux 2 AMI
  instance_type          = "t2.micro"
  key_name               = "personalawskey"          # Update with your key pair
  associate_public_ip_address = true
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]
  subnet_id              = aws_subnet.main.id

  user_data = <<-EOF
  #!/bin/bash
  # Update system packages and install Git and Docker
  sudo yum update -y
  sudo yum install git docker -y
  sudo service docker start
  sudo systemctl enable docker
  sudo usermod -a -G docker ec2-user

  # Configure SSH for GitHub
  mkdir -p /home/ec2-user/.ssh
  chmod 700 /home/ec2-user/.ssh
  echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCjoUeXy2Om49/goSfu6AJvzfFObgmOQjoWsb+fFEBFNDUwaHWIWL6x8vMHXE3MhLCgIsFMUuvkI65mWgieTdyJofHr4A8vCz1urja2Otdc0RB0rm5wmU3zTrHZ2ysfGN3n4iXHINTZENOvImJGQ61E/zcnYwHp3TBifbvsbHLVqchctjbUqGhkuNbsVnAzA3xnr/Licl1+zt9pOpBcc9sVJTJMl5Uwoc7GQK3pVBCDIbsVH6GWmpD6XXVuyeyPNn+dHgQpVJCJEtAEa83U0mlkIALf/bSu4XBiqIl/475X2J7kAruDF+lKwoO3M6rBFimLZlbEsHR1cuFNencSciOb" > /home/ec2-user/.ssh/id_rsa
  chmod 600 /home/ec2-user/.ssh/id_rsa
  ssh-keyscan github.com >> /home/ec2-user/.ssh/known_hosts
  chown -R ec2-user:ec2-user /home/ec2-user/.ssh

  # Clone your private GitHub repository
  su - ec2-user -c "git clone git@github.com:your-repo/agri-pass-backend.git /home/ec2-user/agri-pass-backend"

  # Build Docker image and run the container
  cd /home/ec2-user/agri-pass-backend
  sudo docker build -t agri-pass-backend .
  sudo docker run -d --name agri-pass-backend-container agri-pass-backend

  # Install CloudWatch Agent
  sudo yum install amazon-cloudwatch-agent -y

  # Create CloudWatch configuration file
  cat <<EOT > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
  {
    "logs": {
      "logs_collected": {
        "files": {
          "collect_list": [
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
    Name = "EC2-Docker-GitHub-CloudWatch"
  }
}
