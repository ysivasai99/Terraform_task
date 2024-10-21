provider "aws" {
  region = "ap-southeast-2"
}

# Data source to fetch the default VPC
data "aws_vpc" "default" {
  default = true
}

# IAM Role for EC2 instance
resource "aws_iam_role" "ec2_instance_role" {
  name = "EC2CloudWatchRoleNew1"  # Changed name to avoid conflict

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
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_instance_profile1" {
  name = "EC2InstanceProfileUnique20244"  # Changed name to avoid conflict
  role = aws_iam_role.ec2_instance_role.name
}

# Security Group
resource "aws_security_group" "myec2sg1" {
  name        = "AllowSSHHTTPTraffic"  # Changed name to avoid conflict
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
resource "aws_instance" "docker_ec22" {
  ami           = "ami-084e237ffb23f8f97"  # Amazon Linux 2 AMI
  instance_type = "t2.micro"
  key_name      = "personalawskey"  # Update with your EC2 Key Pair

  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
  security_groups      = [aws_security_group.myec2sg1.name]

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install git -y
    sudo amazon-linux-extras install docker -y
    sudo service docker start
    sudo usermod -a -G docker ec2-user

    # Install CloudWatch Logs agent
    sudo yum install -y awslogs
    sudo systemctl start awslogsd
    sudo systemctl enable awslogsd.service

    # Create CloudWatch log group
    aws logs create-log-group --log-group-name /aws/docker/backend-logs1 --region ap-southeast-2 || true

    # Configure Docker logging to CloudWatch
    cat <<EOT > /etc/docker/daemon.json
    {
      "log-driver": "awslogs",
      "log-opts": {
        "awslogs-region": "ap-southeast-2",
        "awslogs-group": "/aws/docker/backend-logs1",
        "awslogs-stream": "backend-log-stream",
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
    Name = "DockerInstance1"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "docker_log_group1" {
  name              = "/aws/docker/backend-logs1"
  retention_in_days = 7
}

# CloudWatch Log Stream
resource "aws_cloudwatch_log_stream" "backend_log_stream" {
  name           = "backend-log-stream"  # Ensure this name matches the existing log stream
  log_group_name = aws_cloudwatch_log_group.docker_log_group1.name
}

# CloudWatch Log Metric Filter
resource "aws_cloudwatch_log_metric_filter" "error_filter" {
  name           = "ErrorFilter"
  log_group_name = aws_cloudwatch_log_group.docker_log_group1.name
  pattern        = "{ $.level = \"ERROR\" }"  # Change this to match your log structure

  metric_transformation {
    name      = "ErrorCount"
    namespace = "YourNamespace"
    value     = "1"
  }
}

# CloudWatch Alarm for Errors
resource "aws_cloudwatch_metric_alarm" "error_alarm" {
  alarm_name          = "ErrorCountAlarm"
  comparison_operator  = "GreaterThanThreshold"
  evaluation_periods   = "1"
  metric_name         = aws_cloudwatch_log_metric_filter.error_filter.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.error_filter.metric_transformation[0].namespace
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This alarm triggers when the error count exceeds 0."
  alarm_actions       = []  # Specify SNS topic ARN or other action here if needed
  dimensions          = {}
}
