provider "aws" {
  region = "ap-southeast-2"  
}

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

resource "aws_iam_role_policy_attachment" "attach_cw_logs_policy1" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}


resource "aws_iam_instance_profile" "ec2_instance_profile1" {
  name = "EC2InstanceProfile1"
  role = aws_iam_role.ec2_instance_role.name
}

resource "aws_security_group" "ec2_sg1" {
  name        = "allow_ssh_http"
  description = "Allow SSH and HTTP inbound traffic"
  vpc_id      = "vpc-00125d99e226aee56"  

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

resource "aws_instance" "docker_ec2" {
  ami           = "ami-084e237ffb23f8f97"  
  instance_type = "t2.micro"
  key_name      = "personalawskey"  

  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
  security_groups      = [aws_security_group.ec2_sg1.name]

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
        "awslogs-region": "ap-southeast-2",
        "awslogs-group": "docker-container-logs",
        "awslogs-create-group": "true"
      }
    }
    EOT

    sudo service docker restart

    git clone https://github.com/agri-pass/agri-pass-backend.git /home/ec2-user/agri-pass-backend

    cd /home/ec2-user/agri-pass-backend
    docker build -t agri-pass-backend-image .

    docker run -d --name backend-container agri-pass-backend-image
  EOF

  tags = {
    Name = "DockerInstance"
  }
}

resource "aws_cloudwatch_log_group" "docker_log_group" {
  name = "docker-container-logs"
  retention_in_days = 7  # Log retention (can adjust as needed)
}
