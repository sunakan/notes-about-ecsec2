################################################################################
# VPC
################################################################################
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_hostnames = true
  tags = {
    Name = "VPC領域"
  }
}
################################################################################
# インターネットゲートウェイ
################################################################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "VPC領域のIGW"
  }
}
################################################################################
# ルートテーブル
################################################################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "pub-route-table" }
}
################################################################################
# サブネット
#   - サブネットマスク:20
#     - 00001010 00000000 0000|0000 00000000 = 10.0.0.0/20
#     - 最初の16bitは動かせない(vpc定義時に)
#     - よって第3オクテットの左の4bit分がサブネットの最大数=16個
#     - 0000(=0),0001(=16),0010(=32),...
################################################################################
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/20"
  map_public_ip_on_launch = true
  availability_zone = "ap-northeast-1a"
  tags = {
    Name = "pub-subnet-1-tokyo1a"
  }
}
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.16.0/20"
  map_public_ip_on_launch = true
  availability_zone = "ap-northeast-1c"
  tags = {
    Name = "pub-subnet-2-tokyo1c"
  }
}
resource "aws_route_table_association" "associate_routetable_to_subnet_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "associate_routetable_to_subnet_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}
################################################################################
# セキュリティグループ
################################################################################
resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "security group for web"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port = 4567
    to_port   = 4567
    protocol  = "tcp"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "sg for web"
  }
}
