provider "aws" {
  region     = "eu-west-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public1" {
  vpc_id     = "${aws_vpc.main.id}"
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = "true"
  availability_zone = "eu-west-1a"
}

resource "aws_subnet" "public2" {
  vpc_id     = "${aws_vpc.main.id}"
  cidr_block = "10.0.5.0/24"
  map_public_ip_on_launch = "true"
  availability_zone = "eu-west-1b"
}

resource "aws_route_table" "public-route-table" {
    vpc_id = "${aws_vpc.main.id}"

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.gw.id}"
    }
}

resource "aws_db_subnet_group" "default" {
  name       = "dnl-rcon"
  subnet_ids = ["${aws_subnet.public1.id}", "${aws_subnet.public2.id}"]
}

resource "aws_route_table_association" "public1-route-table-association" {
    subnet_id = "${aws_subnet.public1.id}"
    route_table_id = "${aws_route_table.public-route-table.id}"
}

resource "aws_route_table_association" "public2-route-table-association" {
    subnet_id = "${aws_subnet.public2.id}"
    route_table_id = "${aws_route_table.public-route-table.id}"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.main.id}"
}

resource "aws_security_group" "database" {
  name        = "database"
  description = "Security group for database"
  vpc_id = "${aws_vpc.main.id}"

  ingress {
    from_port   = 3306
    to_port     =3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
}

resource "aws_elastic_beanstalk_application" "dnl-rcon" {
  name        = "dnl-rcon"
}

resource "aws_elastic_beanstalk_environment" "dnl-rcon" {
  name                = "dnl-rcon"
  application         = "${aws_elastic_beanstalk_application.dnl-rcon.name}"
  solution_stack_name = "64bit Amazon Linux 2017.03 v2.7.2 running Multi-container Docker 17.03.1-ce (Generic)"
  depends_on = ["aws_internet_gateway.gw"]

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = "${aws_vpc.main.id}"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = "${aws_subnet.public1.id}"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = "${aws_subnet.public1.id}"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "EC2KeyName"
    value     = "id_rsa"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t2.micro"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = "${aws_iam_instance_profile.beanstalk_instance_profile.arn}"
  }

  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "DeploymentPolicy"
    value     = "RollingWithAdditionalBatch"
  }

  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "RollingUpdateType"
    value     = "Health"
  }

  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "BatchSizeType"
    value     = "Fixed"
  }

  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "BatchSize"
    value     = "1"
  }
}

resource "aws_s3_bucket" "foo" {
  bucket = "dnl-rcon-codepipeline-bucket"
  acl    = "private"
}

resource "aws_iam_role" "codepipeline_role" {
  name = "dnl-rcon-codepipeline_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role" "beanstalk_instance_profile_role" {
  name = "dnl-rcon-beanstalk_instance_profile_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "beanstalk_instance_profile" {
  name  = "dnl-rcon-beanstalk_instance_profile"
  role = "${aws_iam_role.beanstalk_instance_profile_role.name}"
}

resource "aws_iam_policy_attachment" "attach_beanstalk_role" {
  name       = "attach_beanstalk_role"
  roles      = ["${aws_iam_role.beanstalk_instance_profile_role.name}"]
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_policy_attachment" "attach_beanstalk_role_web_tier" {
  name       = "attach_beanstalk_role"
  roles      = ["${aws_iam_role.beanstalk_instance_profile_role.name}"]
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline_policy"
  role = "${aws_iam_role.codepipeline_role.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Action": [
              "s3:GetObject",
              "s3:GetObjectVersion",
              "s3:GetBucketVersioning"
          ],
          "Resource": "*",
          "Effect": "Allow"
      },
      {
          "Action": [
              "s3:PutObject"
          ],
          "Resource": [
              "arn:aws:s3:::codepipeline*",
              "arn:aws:s3:::elasticbeanstalk*"
          ],
          "Effect": "Allow"
      },
      {
          "Action": [
              "codecommit:CancelUploadArchive",
              "codecommit:GetBranch",
              "codecommit:GetCommit",
              "codecommit:GetUploadArchiveStatus",
              "codecommit:UploadArchive"
          ],
          "Resource": "*",
          "Effect": "Allow"
      },
      {
          "Action": [
              "codedeploy:CreateDeployment",
              "codedeploy:GetApplicationRevision",
              "codedeploy:GetDeployment",
              "codedeploy:GetDeploymentConfig",
              "codedeploy:RegisterApplicationRevision"
          ],
          "Resource": "*",
          "Effect": "Allow"
      },
      {
          "Action": [
              "elasticbeanstalk:*",
              "ec2:*",
              "elasticloadbalancing:*",
              "autoscaling:*",
              "cloudwatch:*",
              "s3:*",
              "sns:*",
              "cloudformation:*",
              "rds:*",
              "sqs:*",
              "ecs:*",
              "iam:PassRole"
          ],
          "Resource": "*",
          "Effect": "Allow"
      },
      {
          "Action": [
              "lambda:InvokeFunction",
              "lambda:ListFunctions"
          ],
          "Resource": "*",
          "Effect": "Allow"
      },
      {
          "Action": [
              "opsworks:CreateDeployment",
              "opsworks:DescribeApps",
              "opsworks:DescribeCommands",
              "opsworks:DescribeDeployments",
              "opsworks:DescribeInstances",
              "opsworks:DescribeStacks",
              "opsworks:UpdateApp",
              "opsworks:UpdateStack"
          ],
          "Resource": "*",
          "Effect": "Allow"
      },
      {
          "Action": [
              "cloudformation:CreateStack",
              "cloudformation:DeleteStack",
              "cloudformation:DescribeStacks",
              "cloudformation:UpdateStack",
              "cloudformation:CreateChangeSet",
              "cloudformation:DeleteChangeSet",
              "cloudformation:DescribeChangeSet",
              "cloudformation:ExecuteChangeSet",
              "cloudformation:SetStackPolicy",
              "cloudformation:ValidateTemplate",
              "iam:PassRole"
          ],
          "Resource": "*",
          "Effect": "Allow"
      },
      {
          "Action": [
              "codebuild:BatchGetBuilds",
              "codebuild:StartBuild"
          ],
          "Resource": "*",
          "Effect": "Allow"
      }
  ]
}
EOF
}

resource "aws_codepipeline" "foo" {
  name     = "dnl-rcon-pipeline"
  role_arn = "${aws_iam_role.codepipeline_role.arn}"

  artifact_store {
    location = "${aws_s3_bucket.foo.bucket}"
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["test"]

      configuration {
        Owner      = "sandeel"
        Repo       = "dnl-rcon"
        Branch     = "master"
        OAuthToken = "73a65a3735d8e7e07ca3eaaa89785ab8c670fa30"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ElasticBeanstalk"
      input_artifacts = ["test"]
      version         = "1"

      configuration {
        ApplicationName = "${aws_elastic_beanstalk_application.dnl-rcon.name}"
        EnvironmentName = "${aws_elastic_beanstalk_environment.dnl-rcon.name}"
      }
    }
  }
}

output "beanstalk_cname" {
  value = "${aws_elastic_beanstalk_environment.dnl-rcon.cname}"
}
