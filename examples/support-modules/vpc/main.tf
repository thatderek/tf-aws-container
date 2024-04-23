resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

data "aws_availability_zones" "main" {
  state = "available"
}

resource "aws_subnet" "main" {
  count = 2

  availability_zone = data.aws_availability_zones.main.names[count.index]
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${["0", "1"][count.index]}.0/24"
}

output "aws_subnets" {
  value       = aws_subnet.main
  description = "The subnets reated by this VPC module."
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = aws_vpc.main.cidr_block
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "main" {
  count          = 2
  subnet_id      = aws_subnet.main[count.index].id
  route_table_id = aws_route_table.main.id
}

