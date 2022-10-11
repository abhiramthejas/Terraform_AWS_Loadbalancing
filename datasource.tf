data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "available_ami" {

  most_recent      = true
  owners           = ["amazon"]


 filter {
   name = "name"
   values = ["amzn2-ami-kernel-5.10-hvm-*-x86_64-gp2"]
 }

 filter {
   
   name = "virtualization-type"
   values = ["hvm"]
 }

}