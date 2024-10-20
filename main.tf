provider "aws" {
  region = "ap-southeast-2"  # Change this to your desired region
}

//1. Create IAM Role and Policy for EC2 to push logs to CloudWatch
resource "aws_iam_role" "ec2_instance_role" {
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

# Attach the CloudWatch Logs full access policy to the role
resource "aws_iam_role_policy_attachment" "attach_cw_logs_policy" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# 2. Create an EC2 instance profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "EC2InstanceProfile"
  role = aws_iam_role.ec2_instance_role.name
}

# 3. Create a Security Group for EC2 instance
resource "aws_security_group" "ec2_sg" {
  name        = "allow_ssh_http"
  description = "Allow SSH and HTTP inbound traffic"
  vpc_id      = "vpc-07e75756a2cacf2a8"  # Update with your VPC ID

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

# 4. Create EC2 instance and install Docker
resource "aws_instance" "docker_ec2" {
  ami           = "ami-084e237ffb23f8f97"  # Amazon Linux 2 AMI
  instance_type = "t2.micro"
  key_name      = "personalawskey"  # Update with your EC2 Key Pair

  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
  security_groups      = [aws_security_group.ec2_sg.name]

  user_data = <<-EOF
    #!/bin/bash
    # Update the system and install Docker
    sudo yum update -y
    sudo amazon-linux-extras install docker -y
    sudo service docker start
    sudo usermod -a -G docker ec2-user

    # Install CloudWatch Logs agent
    sudo yum install -y awslogs
    sudo systemctl start awslogsd
    sudo systemctl enable awslogsd.service

    # Configure Docker to log to CloudWatch Logs
    cat <<EOT > /etc/docker/daemon.json
    {
      "log-driver": "awslogs",
      "log-opts": {
        "awslogs-region": "us-east-1",
        "awslogs-group": "docker-container-logs",
        "awslogs-create-group": "true"
      }
    }
    EOT

    # Restart Docker service to apply the changes
    sudo service docker restart
  EOF

  tags = {
    Name = "DockerInstance"
  }
}

# 5. Create CloudWatch Log Group
resource "aws_cloudwatch_log_group" "docker_log_group" {
  name = "docker-container-logs"
  retention_in_days = 7  # Log retention (can adjust as needed)
}
