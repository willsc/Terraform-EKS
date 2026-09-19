resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = var.cluster_name })

  lifecycle {
    precondition {
      condition = length(local.availability_zones) == 3 && alltrue([
        for zone in local.availability_zones : contains(data.aws_availability_zones.available.names, zone)
      ])
      error_message = "The cluster requires three available standard availability zones in the provider region."
    }
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = var.cluster_name })
}

resource "aws_subnet" "public" {
  for_each = local.zones

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, tonumber(each.key))
  map_public_ip_on_launch = var.node_subnet_type == "public"
  tags = merge(local.tags, {
    Name                     = "${var.cluster_name}-public-${each.value}"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private" {
  for_each = local.zones

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, tonumber(each.key) + 3)
  map_public_ip_on_launch = false
  tags = merge(local.tags, {
    Name                              = "${var.cluster_name}-private-${each.value}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.cluster_name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = local.zones

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  for_each = local.nat_zones

  domain = "vpc"
  tags   = merge(local.tags, { Name = "${var.cluster_name}-nat-${each.value}" })
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_zones

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = merge(local.tags, { Name = "${var.cluster_name}-nat-${each.value}" })

  depends_on = [aws_internet_gateway.this, aws_route.public_internet, aws_route_table_association.public]
}

resource "aws_route_table" "private" {
  for_each = local.zones

  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.cluster_name}-private-${each.value}" })
}

resource "aws_route" "private_internet" {
  for_each = var.node_subnet_type == "private" ? local.zones : {}

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? "0" : each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = local.zones

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}
