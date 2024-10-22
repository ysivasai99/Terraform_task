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

# Create a security group with SSH access
resource "aws_security_group" "allow_ssh" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Adjust to your IP or 0.0.0.0/0 for all (not recommended for production)
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

# Create an IAM role for EC2 with CloudWatch full access
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

resource "aws_iam_role_policy_attachment" "cloudwatch_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
  role       = aws_iam_role.ec2_role.name
}

# Create an IAM instance profile
resource "aws_iam_instance_profile" "ec2_instance_profile24" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}
# EC2 Instance using the default security group
resource "aws_instance" "my_instance" {
  ami                    = "ami-084e237ffb23f8f97" # Update with your desired AMI
  instance_type         = "t2.micro"               # Adjust as necessary
  key_name              = "personalawskey"         # Update with your key pair
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name
  security_groups       = [aws_security_group.allow_ssh.name]
  subnet_id             = aws_subnet.main.id

  tags = {
    Name = "MyEC2Instance"
  }
}

# Output the public IP
output "instance_ip" {
  value = aws_instance.my_instance.public_ip
}

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
