provider "aws" {
  region = "ap-southeast-2"  # Replace with your AWS region
}

# Create an IAM Role and Policy for EC2 to access CloudWatch Logs
resource "aws_iam_role" "ec2_role" {
  name = "ec2-cloudwatch-role"

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

# Attach CloudWatch Logs full access policy
resource "aws_iam_role_policy_attachment" "cloudwatch_logs_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# Create an Instance Profile for the EC2 instance to assume the IAM role
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# Security group for the EC2 instance
resource "aws_security_group" "instance_sg" {
  name        = "allow_ssh_http"
  description = "Allow SSH and HTTP"
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Update with your specific IP if needed
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

# Launch an EC2 instance with the IAM role and security group
resource "aws_instance" "docker_instance" {
  ami                         = "ami-084e237ffb23f8f97"  # Use your specific AMI ID
  instance_type               = "t2.micro"  # Modify instance type if needed
  key_name                    = "personalawskey"  # Replace with your key pair name
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  security_groups             = [aws_security_group.instance_sg.name]

  # User Data Script to install Docker and configure CloudWatch logs
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install docker -y
    service docker start
    usermod -aG docker ec2-user
    
    # Install the CloudWatch Logs agent
    yum install -y amazon-cloudwatch-agent

    # Create CloudWatch Agent config file for Docker logs
    cat <<EOT >> /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
    {
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/lib/docker/containers/*/*.log",
                "log_group_name": "docker-logs",
                "log_stream_name": "my-app-container-logs"
              }
            ]
          }
        }
      }
    }
    EOT

    # Start CloudWatch Agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
      -s

    # Pull and run Docker container with CloudWatch logs configuration
    docker run -d --name my-app-container \
      --log-driver awslogs \
      --log-opt awslogs-region=ap-southeast-2 \
      --log-opt awslogs-group=docker-logs \
      --log-opt awslogs-create-group=true \
      -p 80:80 agri-pass-backend-image
  EOF

  tags = {
    Name = "DockerInstance"
  }
}

# Output the public IP of the EC2 instance
output "instance_public_ip" {
  value = aws_instance.docker_instance.public_ip
}
