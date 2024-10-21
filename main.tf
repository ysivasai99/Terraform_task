provider "aws" {
  region = "ap-southeast-2"
}

# Data source to fetch the default VPC
data "aws_vpc" "default" {
  default = true
}

# IAM Role for EC2 instance to allow logging to CloudWatch
resource "aws_iam_role" "ec2_cloudwatch_logs_role" {
  name = "EC2-CloudWatch-Logs-Role"

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
  name = "EC2-CloudWatch-Logs-Instance-Profile"
  role = aws_iam_role.ec2_cloudwatch_logs_role.name
}

# Security Group
resource "aws_security_group" "ec2_security_group" {
  name        = "SG-EC2-Docker-Logging"
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

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "docker_logs" {
  name              = "docker-container-logs"
  retention_in_days = 7
}

# EC2 Instance with Docker
resource "aws_instance" "docker_ec2_instance" {
  ami                    = "ami-084e237ffb23f8f97"  # Amazon Linux 2 AMI
  instance_type         = "t2.micro"
  key_name              = "personalawskey"  # Update with your EC2 Key Pair
  iam_instance_profile   = aws_iam_instance_profile.ec2_cloudwatch_logs_profile.name
  security_groups        = [aws_security_group.ec2_security_group.name]

  user_data = <<-EOF
    #!/bin/bash
    # Install Docker
    sudo yum update -y
    sudo amazon-linux-extras install -y docker
    sudo service docker start
    sudo usermod -a -G docker ec2-user

    # Pull your Docker image (replace this with your actual image)
    docker pull your-docker-image

    # Run the Docker container with CloudWatch logging
    docker run -d \
      --log-driver=awslogs \
      --log-opt awslogs-region=ap-southeast-2 \
      --log-opt awslogs-group=docker-container-logs \
      --log-opt awslogs-stream=docker-container-stream \
      your-docker-image
  EOF

  tags = {
    Name = "DockerLoggingEC2Instance"
  }
}

# Output the Instance ID
output "instance_id" {
  value = aws_instance.docker_ec2_instance.id
}
