provider "aws" {
  region = "eu-north-1"
}

resource "aws_instance" "example" {
  ami           = "ami-0c4ba5aa1a6e245f9"
  instance_type = "t3.micro"

  tags = {
    Name = "Imported Instance"
  }
}
