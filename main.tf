
resource "aws_key_pair" "gen_key" {
  key_name   = "generated_key"
  public_key = file("local_key.pub")

tags = {
  Name = "local_key"
}
}

resource "aws_vpc" "myapp_vpc" {

    cidr_block = var.cidr_value
    enable_dns_support = true
    enable_dns_hostnames = true

    tags = {
      "Name" = "${var.project}_VPC"
      "Project" = "${var.project}"
    }
}



resource "aws_security_group" "ssh_sg" {

  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id = aws_vpc.myapp_vpc.id

  ingress {
    description      = "SSH to VPC"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_tls"
  }
  
}

resource "aws_security_group" "http_sg" {

  name        = "allow_http"
  description = "Allow http and https inbound traffic"
  vpc_id = aws_vpc.myapp_vpc.id

  ingress {
    description      = "http to VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "https to VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_tls"
  }
  
}



resource "aws_subnet" "public_subnet" {
  
  count = 3
  vpc_id = aws_vpc.myapp_vpc.id
  cidr_block = cidrsubnet(var.cidr_value, 3, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  
  tags = {
    "Name" = "${var.project}_public_${count.index+1}"
    "Project" = "${var.project}"
  }
}

resource "aws_subnet" "private_subnet" {

  count = 3
  vpc_id = aws_vpc.myapp_vpc.id
  cidr_block = cidrsubnet(var.cidr_value,3,count.index+3)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    "Name" = "${var.project}_private_${count.index+1}"
    "Project" = "${var.project}"
  }
  
}


resource "aws_internet_gateway" "IG" {

  vpc_id = aws_vpc.myapp_vpc.id

  tags = {
    "Name" = "${var.project}_IG"
    "Project" = "${var.project}"
  }
  
}

resource "aws_route_table" "public_route_table" {

  vpc_id = aws_vpc.myapp_vpc.id
  
  route  {
    
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IG.id

  }

  route {
    ipv6_cidr_block  = "::/0"
    gateway_id = aws_internet_gateway.IG.id

  }

  tags = {
    "Name" = "${var.project}_public-route"
    "Project" = "${var.project}"
  }
  
}

resource "aws_eip" "elastic" {
  vpc      = true
}

resource "aws_nat_gateway" "natgateway" {
  
  allocation_id = aws_eip.elastic.id
  subnet_id = aws_subnet.public_subnet[0].id

  tags = {
    "Name" = "${var.project}_NGW"
    "Project" = "${var.project}"
  }

}

resource "aws_route_table" "private_route_table" {

  vpc_id = aws_vpc.myapp_vpc.id

   route  {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.natgateway.id
  }

  tags = {
    "Name" = "${var.project}_private-route"
    "Project" = "${var.project}"
  }
  
}

resource "aws_route_table_association" "public_association" {
  count = 3
  subnet_id = aws_subnet.public_subnet[count.index].id 
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_association" {

  count = 3
  subnet_id = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
  
}

resource "aws_lb_target_group" "myapp_targetgroup" {
  
  name = "${var.project}-Targetgroup"
  protocol = "HTTP"
  port = "80"
  vpc_id = aws_vpc.myapp_vpc.id
  target_type = "instance"
  health_check {
    enabled = true
    port = "80"
    path = "/"
    matcher = "200"

  }

  tags = {
    "Name" = "${var.project}-target_group"
    "Project" = "${var.project}"
  }
}



resource "aws_lb" "myapp_loadbalancer" {

  name = "loadbalancer"
  internal = false
  load_balancer_type = "application"
  subnets = [ aws_subnet.public_subnet[0].id , aws_subnet.public_subnet[1].id, aws_subnet.public_subnet[2].id  ]
  ip_address_type = "ipv4"
  security_groups = [aws_security_group.ssh_sg.id, aws_security_group.http_sg.id]

  
}

resource "aws_lb_listener" "front_end" {

  load_balancer_arn = aws_lb.myapp_loadbalancer.id
  port              = "80"
  protocol          = "HTTP"
  default_action {
    
    type             = "forward"
    target_group_arn = aws_lb_target_group.myapp_targetgroup.id

  }

  
  
}

resource "aws_lb_target_group_attachment" "target_attachment" {

  target_group_arn = aws_lb_target_group.myapp_targetgroup.arn
  target_id        = aws_lb.myapp_loadbalancer.id

  
}






resource "aws_launch_configuration" "myapp_launch_conf" {

  name = "myapp_launch_conf"
  image_id = data.aws_ami.available_ami.id
  instance_type = "t2.micro"
  key_name = aws_key_pair.gen_key.id
  security_groups = [ aws_security_group.ssh_sg.id, aws_security_group.http_sg.id ]
  enable_monitoring = false
  

  
}


resource "aws_autoscaling_group" "myapp_autoscaling" {

  name = "myapp_autoscaling_group"
  launch_configuration = aws_launch_configuration.myapp_launch_conf.id
  vpc_zone_identifier = [ aws_subnet.public_subnet[0].id , aws_subnet.public_subnet[1].id ]
  health_check_type = "EC2"
  max_size = "2"
  min_size = "1"
  desired_capacity = "2"
  
  tag {

  key  = "Name"
  value = "${var.project}_EC2"
  propagate_at_launch = true
}
  
}

resource "aws_autoscaling_attachment" "autoscale_attach" {

  autoscaling_group_name = aws_autoscaling_group.myapp_autoscaling.id
  lb_target_group_arn = aws_lb_target_group.myapp_targetgroup.id

  
}

resource "aws_iam_role_policy" "ec2_policy" {

  name = "ec2_policy"
  role = aws_iam_role.ec2_role.id

  policy = "${file("ec2_policy.json")}"
  
}

resource "aws_iam_role" "ec2_role" {

  name = "testrole"
  assume_role_policy  = "${file("ec2_role.json")}" 

  
}

resource "aws_iam_instance_profile" "ec2_profile" {

  name = "ec2_profile"
  role = aws_iam_role.ec2_role.id

  
}

resource "aws_instance" "Bastion" {

    ami = data.aws_ami.available_ami.id
    instance_type = "t2.micro"
    vpc_security_group_ids = [aws_security_group.ssh_sg.id]
    subnet_id = aws_subnet.public_subnet[0].id
    key_name = aws_key_pair.gen_key.id
    iam_instance_profile = aws_iam_instance_profile.ec2_profile.id

     tags = {
      "Name" = "Bastion"
      "Project" = "${var.project}_Bastion"
    }
  
  
}









