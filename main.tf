resource "null_resource" "provision_ec2" {
  depends_on = [aws_instance.ec2_instance]

  provisioner "remote-exec" {
    inline = [
      # Update the EC2 instance
      "sudo yum update -y",

      # Install Docker, Git, and other necessary tools
      "sudo yum install docker git amazon-cloudwatch-agent -y",

      # Start Docker service
      "sudo systemctl start docker",

      # Generate SSH Key pair for cloning the private GitHub repo
      "ssh-keygen -t rsa -b 4096 -C 'ec2-instance' -f /home/ec2-user/.ssh/id_rsa -N ''",

      # Output the public key to a file for manual addition to GitHub
      "cat /home/ec2-user/.ssh/id_rsa.pub > /home/ec2-user/ssh-public-key.txt",

      # Add GitHub to the known hosts to avoid manual confirmation when connecting
      "ssh-keyscan -t rsa github.com >> /home/ec2-user/.ssh/known_hosts",

      # Use GitHub API to upload the public key programmatically (replace <GITHUB_TOKEN> with your actual token)
      <<-EOF
      curl -X POST -H "Authorization: token ${var.github_token}" \
      -d '{"title":"EC2 SSH Key","key":"$(cat /home/ec2-user/.ssh/id_rsa.pub)"}' \
      https://api.github.com/user/keys
      EOF
      ,

      # Sleep for 20 seconds to give the API time to register the SSH key
      "sleep 20",

      # Clone the private repository into /home/ec2-user directory where ec2-user has write permissions
      "git clone git@github.com:agri-pass/agri-pass-backend.git /home/ec2-user/agri-pass-backend",

      # Build the Docker image from the repository (if Dockerfile exists)
      "cd /home/ec2-user/agri-pass-backend && sudo docker build -t myproject .",

      # Run the Docker container, outputting logs to CloudWatch
      "sudo docker run -d -p 80:80 --log-driver=awslogs --log-opt awslogs-group=docker-logs --log-opt awslogs-stream=${aws_instance.ec2_instance.id} --log-opt awslogs-region=ap-southeast-2 myproject",

      # Configure CloudWatch agent
      <<-EOF
      sudo bash -c 'cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOL
      {
        "logs": {
          "logs_collected": {
            "files": {
              "collect_list": [
                {
                  "file_path": "/var/lib/docker/containers/*.log",
                  "log_group_name": "docker-logs",
                  "log_stream_name": "${aws_instance.ec2_instance.id}"
                }
              ]
            }
          }
        }
      }
      EOL'
      EOF
      ,

      # Start the CloudWatch agent to monitor logs
      "sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a start -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.ec2_key.private_key_pem
      host        = aws_instance.ec2_instance.public_ip
    }
  }
}
