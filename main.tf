provider "aws" {
  region  = "ap-south-1"
  profile = "prakhar"
}

resource "tls_private_key" "mytaskkey"{
  algorithm = "RSA"
}
resource "aws_key_pair" "mytask2key" {
  key_name   = "task2_key"
  public_key =  tls_private_key.mytaskkey.public_key_openssh
}

resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"
}

resource "aws_security_group" "task2tf_sg" {
  name        = "task2_sg"
  description = "Allow SSH and HTTP protocol inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "For ssh, port 22"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    description = "For http, port 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task2_sec_group"
  }
}


resource "aws_instance" "myOS1" {
  ami           = "ami-09a7bbd08886aafdf"
  instance_type = "t2.micro"
  key_name = aws_key_pair.mytask2key.key_name
  security_groups = [aws_security_group.task2tf_sg.name]

    connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.mytaskkey.private_key_pem
    host     = aws_instance.myOS1.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
      "sudo yum install httpd php git -y"
    ]
  }
  tags = {
    Name = "myOS1"
  }
}

resource "aws_efs_file_system" "efs_plus" {
  depends_on = [aws_security_group.task2tf_sg, aws_instance.myOS1]
  creation_token = "efs"

  tags = {
    Name = "my_efs"
  }
}

resource "aws_efs_mount_target" "mount_efs" {
  depends_on = [aws_efs_file_system.efs_plus]
  file_system_id   = aws_efs_file_system.efs_plus.id
  subnet_id = aws_instance.myOS1.subnet_id
  security_groups=[aws_security_group.task2tf_sg.id]
}

resource "null_resource" "cluster" {
  depends_on = [
    aws_efs_file_system.efs_plus,
  ]

    connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.mytaskkey.private_key_pem
    host     = aws_instance.myOS1.public_ip
  }

    provisioner "remote-exec" {
    inline = [
      "sudo echo ${aws_efs_file_system.efs_plus.dns_name}:/var/www/html efs defaults._netdev 0 0>>sudo /etc/fstab",
      "sudo mount ${aws_efs_file_system.efs_plus.dns_name}:/var/www/html/*",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/prakhar1508/cloud_task2.git /var/www/html "
    ]
    }
}

resource "aws_s3_bucket" "task2bucket" {
  bucket = "my-task-2-bucket-1"
  acl    = "public-read"
  force_destroy = true
    tags = {
    Name = "my-task-2-bucket-1"
  }
}

resource "aws_s3_bucket_object" "task2tf_image" {
  depends_on = [
      aws_s3_bucket.task2bucket,
  ]
  key        = "pmb.jpg"
  bucket     = aws_s3_bucket.task2bucket.bucket
  content_type = "image/jpg"
  source     = "C:/Users/user/Desktop/pmb.jpg"
  acl = "public-read"
}

resource "aws_cloudfront_origin_access_identity" "task2cf" {
  comment = "cloud_front"
}

locals{
    s3_origin_id = "aws_s3_bucket.task2bucket.id"
}

resource "aws_cloudfront_distribution" "cf_task2" {
  origin {
    domain_name = aws_s3_bucket.task2bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.task2cf.cloudfront_access_identity_path
    }
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "myimage"

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.task2bucket.bucket_domain_name
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      headers = ["ORIGIN"]
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress = true
  }

  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

      forwarded_values {
      query_string = false
      headers = ["ORIGIN"]
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress = true
  }

 price_class= "PriceClass_200"
 restrictions {
     geo_restriction {
         restriction_type = "none"
     }
 }

 viewer_certificate{
     cloudfront_default_certificate = true
 }
}

resource "null_resource" "null" {
  depends_on = [
    aws_cloudfront_distribution.cf_task2,
  ]

    connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.mytaskkey.private_key_pem
    host     = aws_instance.myOS1.public_ip
  }

    provisioner "remote-exec" {
    inline = [
      "sudo su << EOF",
      "echo \"<img src='http://${aws_cloudfront_distribution.cf_task2.domain_name}/${aws_s3_bucket_object.task2tf_image.key}' height='500' width='500'>\" >> /var/www/html/index.html",
      "EOF",
      "sudo systemctl restart httpd",
    ]
    }
}

data "aws_iam_policy_document" "task2s3_policy" {
  statement {
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.task2bucket.arn}/*"]

  principals {
    type = "AWS"
    identifiers = [aws_cloudfront_origin_access_identity.task2cf.iam_arn]
  }
}
statement {
    actions = [
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.task2bucket.arn]

    principals {
    type = "AWS"
    identifiers = [aws_cloudfront_origin_access_identity.task2cf.iam_arn]
    }
}
}

  resource "aws_s3_bucket_policy" "task2bucket_policy" {
  bucket = aws_s3_bucket.task2bucket.id
  policy = data.aws_iam_policy_document.task2s3_policy.json
  }

output "myOS_Ip" {
    value = aws_instance.myOS1.public_ip
}

output "domain_name" {
    value = aws_cloudfront_distribution.cf_task2.domain_name
}