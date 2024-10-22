provider "aws" {
  region = "ap-southeast-2"
}

# IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "ec2_cloudwatch_role"
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

# Attach policies to the IAM role
resource "aws_iam_role_policy_attachment" "cloudwatch_full_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecs_ec2_role" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_role.name
}

# Security Group
resource "aws_security_group" "ec2_sg" {
  name        = "backend_sg"
  description = "Allow SSH and HTTP"
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
resource "aws_instance" "ec2_instance" {
  ami                         = "ami-084e237ffb23f8f97
  instance_type               = "t2.micro"
  key_name                    = "personalawskey"
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  associate_public_ip_address = true
  security_groups             = [aws_security_group.ec2_sg.name]

  tags = {
    Name = "Docker-EC2"
  }

  user_data = <<-EOF
    #!/bin/bash
    # Install Docker, Git, and update the system
    sudo yum update -y
    sudo yum install git -y
    sudo amazon-linux-extras install docker -y
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker ec2-user

    # Clone the repository
    cd /home/ec2-user
    git clone https://github.com/agri-pass/agri-pass-backend.git
    cd agri-pass-backend
    sudo docker build -t agri-pass-backend-image .

    # Run Docker container with port 80 exposed
    sudo docker run -d --name my-app-container -p 80:80 agri-pass-backend-image

    # Install CloudWatch Agent
    sudo yum install amazon-cloudwatch-agent -y

    # Create CloudWatch Agent configuration file
    sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<-CONFIG
    {
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/lib/docker/containers/*/*.log",
                "log_group_name": "docker-logs",
                "log_stream_name": "{instance_id}"
              }
            ]
          }
        }
      }
    }
    CONFIG

    # Start the CloudWatch Agent
    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

    # Run the Docker container with CloudWatch log driver
    sudo docker run -d --name my-app-containernew \
      --log-driver awslogs \
      --log-opt awslogs-region=ap-southeast-2 \
      --log-opt awslogs-group=docker-logs \
      --log-opt awslogs-create-group=true \
      -p 80:80 agri-pass-backend-image
  EOF
}

# Output EC2 Instance Public IP
output "ec2_instance_public_ip" {
  value = aws_instance.ec2_instance.public_ip
}
