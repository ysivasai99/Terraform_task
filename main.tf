resource "aws_instance" "docker_ec2" {
  ami           = "ami-084e237ffb23f8f97"  # Amazon Linux 2 AMI
  instance_type = "t2.micro"
  key_name      = "personalawskey"  # Update with your EC2 Key Pair

  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
  security_groups      = [aws_security_group.ec2_sg.name]

  user_data = <<-EOF
    #!/bin/bash
    # Update the system and install Docker and Git
    sudo yum update -y
    sudo amazon-linux-extras install docker -y
    sudo yum install git -y
    sudo service docker start
    sudo usermod -a -G docker ec2-user

    sudo yum install -y awslogs
    sudo systemctl start awslogsd
    sudo systemctl enable awslogsd.service

    cat <<EOT > /etc/docker/daemon.json
    {
      "log-driver": "awslogs",
      "log-opts": {
        "awslogs-region": "ap-southeast-2",
        "awslogs-group": "/aws/docker/backend-logs",
        "awslogs-stream": "backend-container-logs",
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
