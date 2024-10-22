provider "aws" {
  region = "ap-southeast-2"
}

resource "aws_iam_role" "ec2_cloudwatch_role" {
  name = "ec2_cloudwatch_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_full_access" {
  role       = aws_iam_role.ec2_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}


resource "aws_instance" "ec2_instance" {
  ami           = "ami-084e237ffb23f8f97" # Use your AMI ID
  instance_type = "t2.micro"
  key_name      = "personalawskey"
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
  security_groups = [aws_security_group.default_sg.name]
  tags = {
    Name = "EC2-with-Security-Group"
  }
}
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install git -y
              amazon-linux-extras install docker -y
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ec2-user
              # Clone your repository
              ssh-keygen -t rsa -b 4096 -C "ysivasai99@gmail.com"
              cat ~/.ssh/id_rsa.pub
              clip < ~/.ssh/id_rsa.pub
              

              mkdir -p ~/.ssh
              echo "YOUR_SSH_PRIVATE_KEY" > ~/.ssh/id_rsa
              chmod 600 ~/.ssh/id_rsa
              ssh-keyscan github.com >> ~/.ssh/known_hosts
              git clone https://github.com/your-repo/agri-pass-backend.git
              sleep 30
              cd agri-pass-backend
              docker build -t agri-pass-backend-image .
              sleep 30
              docker run -d --name my-app-container -p 80:80 agri-pass-backend-image
              sleep 30
              yum install amazon-cloudwatch-agent -y
              # Create the CloudWatch Agent configuration file
              cat << 'EOT' > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
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
              EOT
              sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
              EOF
}
