provider "aws" {
  region = "ap-southeast-2"
}

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

resource "aws_iam_role_policy_attachment" "cloudwatch_logs_attachment" {
  role       = aws_iam_role.ec2_cloudwatch_logs_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_instance_profile" "ec2_cloudwatch_logs_profile" {
  name = "EC2-CloudWatch-Logs-Instance-Profile-${random_id.unique_id.hex}"
  role = aws_iam_role.ec2_cloudwatch_logs_role.name
}

resource "random_id" "unique_id" {
  byte_length = 4
}


data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "ec2_security_group" {
  name        = "EC2-Docker-Security-Group"
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

resource "aws_cloudwatch_log_group" "ec2_logs_group" {
  name              = "/aws/ec2/instance-logs"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "docker_logs_group" {
  name              = "/aws/docker/container-logs"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_stream" "ec2_log_stream" {
  name           = "ec2-instance-log-stream"
  log_group_name = aws_cloudwatch_log_group.ec2_logs_group.name
}

resource "aws_cloudwatch_log_stream" "docker_log_stream" {
  name           = "docker-container-log-stream"
  log_group_name = aws_cloudwatch_log_group.docker_logs_group.name
}

resource "aws_instance" "docker_ec2_instance" {
  ami             = "ami-084e237ffb23f8f97"  # Amazon Linux 2 AMI
  instance_type   = "t2.micro"
  key_name        = "personalawskey"     # Replace with your EC2 key pair

  iam_instance_profile = aws_iam_instance_profile.ec2_cloudwatch_logs_profile.name
  security_groups      = [aws_security_group.ec2_security_group.name]

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y

    # Install Docker
    sudo amazon-linux-extras install docker -y
    sudo service docker start
    sudo usermod -a -G docker ec2-user

    # Install Git
    sudo yum install -y git

    # Clone the repository
    git clone https://github.com/agri-pass/agri-pass-backend.git /home/ec2-user/agri-pass-backend

    # Navigate to the repository directory
    cd /home/ec2-user/agri-pass-backend

    # Run Docker
    docker-compose up -d

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

    # Run Docker container with CloudWatch logging
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

output "instance_id" {
  value = aws_instance.docker_ec2_instance.id
}

output "instance_public_ip" {
  value = aws_instance.docker_ec2_instance.public_ip
}
