
#Create aws key pair value for the instance
resource "tls_private_key" "webserver_private_key" {
    algorithm = "RSA"
    rsa_bits = 4096
}
resource "local_file" "private_key" {
    content = tls_private_key.webserver_private_key.private_key_pem
    filename = "webserver_key.pem"
    file_permission = "0400"
}

resource "aws_key_pair" "webserver_key" {
    key_name = "webserver"
    public_key = tls_private_key.webserver_private_key.public_key_openssh
}


#Create security group allowing ssh and http traffic
resource "aws_security_group" "allow_http_ssh" {
  name        = "allow_http"
  description = "Allow http inbound traffic"
ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
 
  }
ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
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
    Name = "allow_http_ssh"
  }
}

#Create ec2 instance
resource "aws_instance" "webserver" {
  ami           = "ami-0f403e3180720dd7e"
  instance_type = "t2.micro" 
  key_name  = aws_key_pair.webserver_key.key_name
  security_groups=[aws_security_group.allow_http_ssh.name]
tags = {
    Name = "webserver_task1"
  }
  connection {
        type    = "ssh"
        user    = "ec2-user"
        host    = aws_instance.webserver.public_ip
        port    = 22
        private_key = tls_private_key.webserver_private_key.private_key_pem
    }
  provisioner "remote-exec" {
        inline = [
        "sudo yum install httpd php git -y",
        "sudo systemctl start httpd",
        "sudo systemctl enable httpd",
        ]
    }
}

#Create EBS volume
resource "aws_ebs_volume" "my_volume" {
    availability_zone = aws_instance.webserver.availability_zone
    size              = 1
    tags = {
        Name = "webserver-pd"
    }
}

#Attach EBS volume to ec2
resource "aws_volume_attachment" "ebs_attachment" {
    device_name = "/dev/xvdf"
    volume_id   =  aws_ebs_volume.my_volume.id
    instance_id = aws_instance.webserver.id
    force_detach =true     
   depends_on=[aws_instance.webserver,aws_ebs_volume.my_volume]
}

#Create S3 bucket
resource "aws_s3_bucket" "task1_s3bucket" {
  bucket = "mohit-web-app-01"
  acl    = "public-read"
  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }    
}

#Add objects to S3 from github
resource "null_resource" "images_repo" {
  provisioner "local-exec" {
    command = "git clone https://github.com/mohit2709-repo/myimages.git my_images"
  }
  provisioner "local-exec"{ 
  when        =   destroy
        command     =   "rm -rf my_images"
    }
}
resource "aws_s3_bucket_object" "sun_image" {
  bucket = aws_s3_bucket.task1_s3bucket.bucket
  key    = "sun.jpg"
  source = "my_images/sun.jpg"
  acl="public-read"
   depends_on = [aws_s3_bucket.task1_s3bucket,null_resource.images_repo]
}

#Create Cloudfront resource
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.task1_s3bucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.task1_s3bucket.id
 
     custom_origin_config {
            http_port = 80
            https_port = 443
            origin_protocol_policy = "match-viewer"
            origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
        }
  }
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.task1_s3bucket.id
forwarded_values {
      query_string = false
cookies {
        forward = "none"
      }
    }
   viewer_protocol_policy = "allow-all"
  }
 price_class = "PriceClass_200"
restrictions {
        geo_restriction {
        restriction_type = "none"
        }
    }
 viewer_certificate {
    cloudfront_default_certificate = true
  }
 depends_on = [aws_s3_bucket.task1_s3bucket]
}

#Clone php code from git to ebs volume

resource "null_resource" "nullremote"  {
depends_on = [  aws_volume_attachment.ebs_attachment,aws_cloudfront_distribution.s3_distribution
   ]
    connection {
        type    = "ssh"
        user    = "ec2-user"
        host    = aws_instance.webserver.public_ip
        port    = 22
        private_key = tls_private_key.webserver_private_key.private_key_pem
    }
   provisioner "remote-exec" {
        inline  = [
     "sudo mkfs.ext4 /dev/xvdf",
     "sudo mount /dev/xvdf /var/www/html",
     "sudo rm -rf /var/www/html/*",
     "sudo git clone https://github.com/mohit2709-repo/myimages.git /var/www/html/",
     "sudo su << EOF",
            "echo \"${aws_cloudfront_distribution.s3_distribution.domain_name}\" >> /var/www/html/path.txt",
            "EOF",
     "sudo systemctl restart httpd"
 ]
    }
}

output "IP"{
 value=aws_instance.webserver.public_ip
}