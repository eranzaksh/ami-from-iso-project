provider "aws" {
  region = var.region
  profile = "eran"
}


resource "aws_security_group" "sg_iso" {
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
      from_port = 22
      to_port = 22
      protocol = "tcp"
      cidr_blocks = var.allowed_ssh_ips
  }
}
resource "aws_instance" "ami-from-iso" {
  ami           = var.ami
  instance_type = "t3.micro"
  key_name = var.key_name
  vpc_security_group_ids = [aws_security_group.sg_iso.id]
  tags = {
    Name = "EC2 with AMI from ISO"
  }
}
