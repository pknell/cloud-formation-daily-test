# Terraform Template for AWS CloudFormation Daily Testing
*© 2018 Paul Knell, NVISIA LLC*

This is part 2 of a 2-part series. In this part, I present a Terraform template that's roughly equivalent
to the [CloudFormation (CF) template presented in part 1](https://github.com/pknell/cloud-formation-daily-test/blob/master/blog-cf.md).
Although on a real project you wouldn't be using a Terraform template to test
a CloudFormation template (as they're competing technologies so you'd probably use either one or the other), this
article presents the Terraform version for purposes of comparison. We'll be able to see
how the two technologies are similar, and also highlight some of the differences.

## Install Terraform
In addition to having an AWS account, you'll also need to install Terraform and add it to your path.
Refer to the [Terraform installation documentation](https://www.terraform.io/intro/getting-started/install.html) for details.

You'll need to give Terraform access to your AWS account, by following these steps:
1. Create an Access Key and Secret Access Key, refer to [https://aws.amazon.com/premiumsupport/knowledge-center/create-access-key/](https://aws.amazon.com/premiumsupport/knowledge-center/create-access-key/)
1. Pass the access key and secret access key into Terraform, refer to [https://terraform.io/docs/providers/aws/index.html](https://terraform.io/docs/providers/aws/index.html)

For step 2 above, the easiest approach is the "Shared Credentials File"--merely create a ".aws/credentials" file in
your user's home directory with the following content:
```
[default]
aws_access_key_id=YOUR-ACCESS-KEY
aws_secret_access_key=YOUR-SECRET-ACCESS-KEY
```

## Create an SSH Key Pair
You will need an SSH Key Pair in EC2 because it is required by the "Docker for AWS" CF template that this example is
using. If you do not have one, [create it using the EC2 console](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#having-ec2-create-your-key-pair)
and remember its name for the next step.

## Run Terraform
Unlike CloudFormation, you will not use the AWS console to run the template file. Instead, you need to have the files
locally in a new directory.  You can download the files from my public GitHub repository: [https://github.com/pknell/cloud-formation-daily-test](https://github.com/pknell/cloud-formation-daily-test).
You can clone the repository with a git client, or merely [download and extract the zip](https://github.com/pknell/cloud-formation-daily-test/archive/master.zip).

To run the template, open a shell into the extracted directory, and run "terraform init". This will download and install
the Terraform plugins that are used by the templates found in the current directory.  For this example, these are
the provider-aws plugin and the provider-archive plugin.
 
Next, run "terraform apply". You will be prompted to enter the name of your SSH Key Pair, to confirm that you want to
continue, and then Terraform will create all of the template's resources. The next section of this blog explains each
resource.

** Disclaimer: You are responsible for charges to your AWS account, therefore please remember to clean-up when you're done
to avoid uneccessary costs. Refer to the "Clean-up" section near the end of this article. **

The "terraform apply" command also creates a terraform.tfstate file in the current directory. This file is used by 
Terraform to store information regarding created resources, so they can be updated or removed. For AWS, there is an
[S3 Backend](https://www.terraform.io/docs/backends/types/s3.html) that replaces the local tfstate file with an S3 bucket
and DynamoDB (for locking)--you'll want to use this if working on a team collaboratively, but for this example it's fine
to use the local (default) backend.

When "terraform apply" completes successfully, you'll have all the resources needed for the automatic daily test of the
CloudFormation template: the IAM policies and roles, the CloudWatch Events (Rules), the Lambda functions and Lambda
permissions. The stack (for "Docker for AWS") will be automatically created and removed, per the schedule of the cron
expressions (as was explained in [part 1 of this series](https://github.com/pknell/cloud-formation-daily-test/blob/master/blog-cf.md)).

## Terraform Walk-Through
The Terraform template file is called [start-stop-environment.tf](https://github.com/pknell/cloud-formation-daily-test/blob/master/start-stop-environment.tf).
This file starts with a provider and a couple data sources:
```
provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
```
This provider specifies the region, which is required when using Terraform with AWS. 
If the region was omitted, Terraform will prompt for it (similar to the prompt for the ssh_key_name).
The aws_caller_identity and aws_region data sources are used later in the template when we need to reference
the current region and account ID.  If you're using a different region (other than us-east-1), such as if you're SSH
Key Pair is in a different region, then you'll need to adjust the region in the template file (or remove that line, so
that Terrform will prompt for it).

After the provider, the template declares a variable called ssh_key_name. This is needed because it's a required
parameter to the CF template (for Docker) that we're running. Terraform prompts the user for this value if it's not
provided via the command-line or arguments file. We'll reference this variable later when we define the CloudWatch rule.
```
variable "ssh_key_name" {
  type = "string"
}
```

The template continues with a few IAM-related resources, needed so that the Lambda functions will have a role with the
necessary permissions to create and delete the CF stack:
```
resource "aws_iam_policy" "manage_environment_iam_policy" {
  name = "ManageEnvPolicy"
  policy = "${file("manage-environment-policy.json")}"
}

resource "aws_iam_role" "manage_environment_iam_role" {
  name = "ManageEnvRole"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy_attachment" "manage_environment_iam_policy_attachment" {
    name = "ManageEnvPolicyAttachment"
    policy_arn = "${aws_iam_policy.manage_environment_iam_policy.arn}"
    roles = ["${aws_iam_role.manage_environment_iam_role.name}"]
}
```
The role (called "manage_environment_iam_role") is associated to a policy (called "manage_environment_iam_policy") 
by means of the "manage_environment_iam_policy_attachment". The policy is separated in a JSON file that follows the
AWS policy JSON format. The policy I'm using includes all the permissions needed for the Docker CF template but
intentionally excludes items such as Billing, KMS, and deletion of CloudTrail logs. If you're using your project's
CF template, instead of the one used in this example, you'll need to create a policy 
(or customize this one) to meet the needs of your application stack and organization's requirements.

With the IAM role available, we can move on to creation of the Lambda functions:
```
data "archive_file" "start_environment_lambda_zip" {
    type        = "zip"
    source_dir  = "start_env_lambda"
    output_path = "lambda-packages/start_environment_lambda_payload.zip"
}

resource "aws_lambda_function" "start_environment_lambda" {
  filename         = "lambda-packages/start_environment_lambda_payload.zip"
  function_name    = "StartEnvironment"
  role             = "${aws_iam_role.manage_environment_iam_role.arn}"
  handler          = "index.handler"
  source_code_hash = "${data.archive_file.start_environment_lambda_zip.output_base64sha256}"
  runtime          = "nodejs8.10"
  memory_size      = 128
  timeout          = 15
}

data "archive_file" "stop_environment_lambda_zip" {
    type        = "zip"
    source_dir  = "stop_env_lambda"
    output_path = "lambda-packages/stop_environment_lambda_payload.zip"
}

resource "aws_lambda_function" "stop_environment_lambda" {
  filename         = "lambda-packages/stop_environment_lambda_payload.zip"
  function_name    = "StopEnvironment"
  role             = "${aws_iam_role.manage_environment_iam_role.arn}"
  handler          = "index.handler"
  source_code_hash = "${data.archive_file.stop_environment_lambda_zip.output_base64sha256}"
  runtime          = "nodejs8.10"
  memory_size      = 128
  timeout          = 15
}
```

Here we create each Lambda function by referencing both the IAM role as well as the Lambda function's code. The
file format for the code varies depending on the language. For this example, since I used NodeJS, the format is a zip
file that contains at least one ".js" file. The "archive_file" data sources are used to create the zip file when
Terraform executes. The Lambda service will extract the contents of the zip and run the
JavaScript function identified by the handler "index.handler". The name of the handler is really the base name of the
file "index.js", followed by a dot, followed by the name of the exported JavaScript function. Here's the contents
of the index.js of the "start_environment_lambda_payload.zip":
```
exports.handler = function(event, context, callback) {

   var AWS = require('aws-sdk');
   var cloudformation = new AWS.CloudFormation();

   var params = {
     StackName: event.stackName, /* required */
     Capabilities: [
       'CAPABILITY_IAM'
     ],
     EnableTerminationProtection: false,
     OnFailure: 'ROLLBACK', // DO_NOTHING | ROLLBACK | DELETE,
     Parameters: [
       {
         ParameterKey: 'KeyName',
         ParameterValue: event.keyPairName
       },
       {
           ParameterKey: 'ManagerSize',
           ParameterValue: event.managerSize || '1'
       },
       {
           ParameterKey: 'ClusterSize',
           ParameterValue: event.clusterSize || '1'
       }
     ],
     Tags: [
       {
         Key: 'CloudFormationStack',
         Value: event.stackName
       }
     ],
     TemplateURL: 'https://editions-us-east-1.s3.amazonaws.com/aws/stable/Docker.tmpl',
     TimeoutInMinutes: 20
   };
   cloudformation.createStack(params, function(err, data) {
     if (err) {
        callback("Error creating the Stack: "+err);
     }
     else {
        callback(null, "Success creating the Stack.");
     }
   });
}
```
All we're doing in this function is:
1. Import aws-sdk so that we can access the CloudFormation API
1. Create the parameters needed to create a Stack. The parameter called "Parameters" is for the CF template's 
parameters (as opposed to parameters of the createStack call).
1. Initiate creation of the Stack

The function for stopping the environment is similar:
```
exports.handler = function(event, context, callback) {

   var AWS = require('aws-sdk');
   var cloudformation = new AWS.CloudFormation();

    var params = {
      StackName: event.stackName /* required */
    };
   cloudformation.deleteStack(params, function(err, data) {
     if (err) {
        callback("Error deleting the Stack: "+err);
     }
     else {
        callback(null, "Success deleting the Stack.");
     }
   });
}
```

Now that we have Lambda functions that can call CloudFormation with the permissions necessary for successful stack 
creation/deletion, the last step is to define the CloudWatch Rules that will trigger those functions on a schedule:
```
resource "aws_cloudwatch_event_rule" "start_environment_rule" {
  name                = "StartEnvironmentRule"
  schedule_expression = "cron(30 14 ? * 2-6 *)"
}

resource "aws_cloudwatch_event_rule" "stop_environment_rule" {
  name                = "StopEnvironmentRule"
  schedule_expression = "cron(0 15 ? * 2-6 *)"
}

resource "aws_cloudwatch_event_target" "start_environment_rule_target" {
  target_id = "start_environment_rule_target"
  rule      = "${aws_cloudwatch_event_rule.start_environment_rule.name}"
  arn       = "${aws_lambda_function.start_environment_lambda.arn}"
  input     = <<EOF
{ "stackName": "MyStack", "keyPairName": "${var.ssh_key_name}" }
EOF
}

resource "aws_cloudwatch_event_target" "stop_environment_rule_target" {
  target_id = "stop_environment_rule_target"
  rule      = "${aws_cloudwatch_event_rule.stop_environment_rule.name}"
  arn       = "${aws_lambda_function.stop_environment_lambda.arn}"
  input     = <<EOF
{ "stackName": "MyStack" }
EOF
}
```

Here you can see the cron expressions that define when each rule is triggered, as well as each "target" that specifies which Lambda function is called and the parameters (as JSON) to pass into the function.  Notice that the "input" for "start_environment_rule_target" includes the "ssh_key_name" variable--so that the nodes of the Docker Swarm cluster will allow SSH access only by the specified key.

After creating the rules, we need to authorize them to call the Lambda functions:
```
resource "aws_lambda_permission" "allow_cloudwatch_start_env" {
  statement_id   = "AllowExecutionFromCloudWatch"
  action         = "lambda:InvokeFunction"
  function_name  = "${aws_lambda_function.start_environment_lambda.function_name}"
  principal      = "events.amazonaws.com"
  source_arn     = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/StartEnvironmentRule"
}

resource "aws_lambda_permission" "allow_cloudwatch_stop_env" {
  statement_id   = "AllowExecutionFromCloudWatch"
  action         = "lambda:InvokeFunction"
  function_name  = "${aws_lambda_function.stop_environment_lambda.function_name}"
  principal      = "events.amazonaws.com"
  source_arn     = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/StopEnvironmentRule"
}
```

As you can see, if you've worked through the previous article (part 1 of this series), this is all very similar to what
we did with CloudFormation; it's mostly just a different syntax.  Error notification is also similar--for a Terraform
example, you can refer to [my error-notify-using-sms branch](https://github.com/pknell/cloud-formation-daily-test/tree/error-notify-using-sms),
particularly the file "[error-notification.tf](https://github.com/pknell/cloud-formation-daily-test/raw/error-notify-using-sms/error-notification.tf)".

## Comparison: Terraform vs. CloudFormation
This is a comparison that's written in the context of my experience in developing this article's templates.
As such, not all aspects or features are covered, but just those that were
significant in my experience. Many of these differences are described accurately [in this article](https://cloudonaut.io/cloudformation-vs-terraform/),
but here I provide some detailed examples.

#### Template Syntax
Other than Terraform's multi-provider support (i.e., support for various Cloud vendors), the main difference between 
Terraform and CloudFormation is the syntax of the template files. CloudFormation supports both JSON and YAML formats,
whereas Terraform supports both JSON and a proprietary [HashiCorp Configuration Language (HCL)](https://github.com/hashicorp/hcl).
In both cases, the non-JSON option is more concise and easier for human editing than JSON. Compared to CloudFormation's
YAML syntax, Terraform's HCL syntax is more concise and easier to work with. This is partly because of
Terraform's [interpolation syntax](https://www.terraform.io/docs/configuration/interpolation.html)--for example, accessing
a resource's ARN is a one-liner in Terraform:
```
role = "${aws_iam_role.manage_environment_iam_role.arn}"
```
But it's 3 lines in CloudFormation:
```
Role: !GetAtt
  - ManageEnvRole
  - Arn
```

#### Multi-file Support
Both CloudFormation and Terraform support dividing a template into multiple files, however they support this differently.
CloudFormation uses the concept of [nested stacks](https://aws.amazon.com/blogs/devops/use-nested-stacks-to-create-reusable-templates-and-support-role-specialization/),
where the parent template references the file of the child. Template parameters and outputs are then used to pass data
between the various nested stacks. The approach used by Terraform is that all template files in the current directory
are included (as a default module), and there is an "override" filename convention to specify files that are processed
last and take precedence.
Furthermore, [additional modules can be referenced](https://www.terraform.io/docs/modules/usage.html), and thus instantiated. The
Terraform approach is easier to work with, in my opinion, because the developer does not need to explicitly reference 
each file (within a module) and does not need to create parameters and outputs for passing data within a module.

Another important observation, is that using multiple files in CloudFormation requires that the files be placed into S3,
whereas with Terraform they can be local (or there are [many other options](https://www.terraform.io/docs/modules/sources.html),
including S3). Being able to skip the step of copying files to S3 was very convenient. A similar constraint also
exists for the code of the Lambda functions--with CloudFormation the code would have needed to be zip'ed and placed into S3
if it wasn't embedded within the template, whereas with Terraform it was easy to reference a local file.

#### Development Tooling
Terraform usage is entirely command-line based. I found the commands easy to work with, and output easy to understand.
Error messages were clear and made it easy to understand how to fix problems. There's a command to apply changes, and
a different command to merely view what the changes will be. While CloudFormation also has a preview feature, I prefer the
 clarity of Terraform's output over that of CloudFormation. For example, if I update the CloudFormation stack to change
 the StartRule's cron expression, it will show me the impacted resources, but the details of exactly which property is
 being changed is shown as verbose JSON without the before/after values:
 
![CloudFormation Preview Change](https://github.com/pknell/cloud-formation-daily-test/blob/master/comparison-images/cf-preview-change.png)
 
However, Terraform prints a friendly message including before/after values:

![Terraform Preview Change](https://github.com/pknell/cloud-formation-daily-test/blob/master/comparison-images/tf-preview-change.png)

CloudFormation can be used by command-line (as is Terraform) via the AWS CLI. However, it can also be graphical via 
web-browser. There is a [Template Designer tool](https://console.aws.amazon.com/cloudformation/designer/) that helps
when writing new templates--but it only sets up the skeleton; you have to add property details directly into the
JSON or YAML. However, I did find it useful, particularly because it generates a nice dependency diagram of all the
template's resources. Terraform also has a way to generate a dependency diagram with the "terraform graph" command,
but CF's Designer is a graphical editor.

There's also a CloudFormer tool--however it is a Beta version, and it requires a number of manual steps that the developer
 must do to the generated template to bring it up to the desired quality.  Despite these drawbacks, it is sometimes
 useful for saving time when creating new templates versus writing them entirely from scratch or with the Designer.

Terraform does not have an equivalent mechanism for generating a
template--however, for most resources there is support for an ["import" feature](https://www.terraform.io/docs/import/index.html).
While this feature does not (yet) actually generate templates, it does facilitate the creation of a template based on 
existing resources by using a process as follows:
 1. Create resources using the AWS console and test functionality
 1. Write skeletons for those resources into the template file
 1. Run "terraform import ..." commands to bring those resources into the local Terraform State
(terraform.tfstate). Each resource needed to be separately imported.
 1. Run "terraform plan" to see the details for each new resource
 1. Use those details to update the template file (the properties of each new resource)
 1. Run "terraform plan" again to view differences, repeating until no more differences exist
 
This process got me very close to having a working template, and seemed to be much quicker than the many develop/test
cycles that would have otherwise been needed to develop the template from scratch.  However, I did come across a number
of resource types where Import was not supported.

#### API Completeness
The CloudFormation User Guide documents the [list of AWS services that it supports](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-supported-resources.html).
The [reference documentation for the Terraform AWS Provider](https://www.terraform.io/docs/providers/aws/index.html)
documents the AWS services that Terraform supports. When comparing the lists, one finds that both are exhaustive and
seemingly complete. This stands to reason due to the partnership [between Hashicorp and AWS](https://www.hashicorp.com/integrations/aws),
and the fact that Terraform is Open Source.
When working with Terraform, I only ran into one AWS feature that was not directly supported: the "email" protocol of an SNS Subscription.
The lack of support for this is documented in the [aws_sns_topic_subscription documentation](https://www.terraform.io/docs/providers/aws/r/sns_topic_subscription.html).
I worked around this by using SMS instead, as it was readily supported by both CF and Terraform.

## Clean-up
You can delete all the resources that Terraform created by returning to the shell (in the directory containing the project files)
 and running the command "terraform destroy". If you want to leave the resources in place, but disable the
daily test, you can simply disable both CloudWatch rules. You can do this in the AWS console, or you can edit both
of the aws_cloudwatch_event_rule resources in start-stop-environment.tf so that they contain "enabled = false", and 
then run "terraform apply".
 
