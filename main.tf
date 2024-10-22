provider "aws" {
  region = "ap-southeast-2"
}

# IAM Role and Policy for EC2 Instance with CloudWatchFullAccess
resource "aws_iam_role" "ec2_role" {
  name = "ec2_cloudwatch_role_new"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Attach the AWS-managed CloudWatchFullAccess policy to the EC2 role
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_full_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

# IAM instance profile to attach the role to the EC2 instance
resource "aws_iam_instance_profile" "ec2_instance_profile_new" {
  name = "ec2_instance_profile_new"
  role = aws_iam_role.ec2_role.name
}

# Security Group for EC2 Instance
resource "aws_security_group" "ec2_sg_new" {
  name        = "backend_sg_new"
  description = "Allow SSH and HTTP"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # SSH access (you can restrict this)
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # HTTP access
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create CloudWatch Log Group
resource "aws_cloudwatch_log_group" "backend_log_group" {
  name              = "/ecs/backend-docker-logs"
  retention_in_days = 7  # Set retention for logs
}

# EC2 Instance Setup
resource "aws_instance" "ec2_instance" {
  ami                         = "ami-084e237ffb23f8f97"  # Updated AMI
  instance_type               = "t2.micro"
  key_name                    = "personalawskey"
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile_new.name
  associate_public_ip_address = true

  tags = {
    Name = "Backend-EC2"
  }

  security_groups = [aws_security_group.ec2_sg_new.name]

  user_data = <<-EOF
    #!/bin/bash
    # Update system and install Git
    sudo yum update -y
    sudo yum install git -y

    # Install Docker
    sudo amazon-linux-extras install docker -y
    sudo service docker start
    sudo usermod -a -G docker ec2-user

    # Clone the backend repository from GitHub
    cd /home/ec2-user
    git clone https://github.com/agri-pass/agri-pass-backend.git
    cd agri-pass-backend

    # Build and run Docker container
    sudo docker build -t backend-app .
    sudo docker run -d backend-app

    # Install CloudWatch Agent
    sudo yum install -y amazon-cloudwatch-agent

    # Create CloudWatch Logs configuration file
    cat <<EOT >> /opt/aws/amazon-cloudwatch-agent/bin/config.json
    {
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/lib/docker/containers/*/*.log",
                "log_group_name": "/ecs/backend-docker-logs",
                "log_stream_name": "backend-app-log-stream-{container_id}",
                "timezone": "UTC"
              }
            ]
          }
        }
      }
    }
    EOT

    # Start CloudWatch Agent
    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s
    sudo systemctl enable amazon-cloudwatch-agent
    sudo systemctl start amazon-cloudwatch-agent
  EOF
}

# Outputs
output "ec2_instance_public_ip" {
  value = aws_instance.ec2_instance.public_ip
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.backend_log_group.name
}
