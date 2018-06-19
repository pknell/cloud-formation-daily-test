# Infrastructure Automated Testing

When it comes to Amazon Web Services (AWS), most infrastructure scripting is done using either
CloudFormation (CF), which is an AWS service, or Terraform (an open-source tool). These tools allow for
the creation of template files that represent the configuration of your cloud environment thereby allowing
you to easily create additional similar environments for purposes such as testing, quality assurance, and
disaster recovery. Since the template itself is code, it should be tested periodically to ensure that it
still works so you can have confidence in the functionality of the template itself.  For example, a template
developed during an initial development phase might not be needed again until months later when a second
phase begins. A simple daily test of the template will allow your team to be notified if the template
happens to break (perhaps due to updates of dependent services/packages).

This blog works through setting up this kind of daily test.
For the sake of an example, we are using the "Docker for AWS Community Edition" template as the environment
that the test stands-up and then tears-down, but the idea is that you would use your project's template
instead.
The image below depicts the entire setup, and we'll walk through a Terraform script that creates this setup.
All you will need is an AWS account and a local installation of Terraform. 

![Overview Diagram](https://github.com/pknell/cloud-formation-daily-test/blob/master/diagram.png)

CloudWatch Rules are used to trigger Lambda functions. You can tweak the rules' cron expression to adjust
the start/stop times (e.g., you could adjust them to match your workday and then use the environment
during the day for additional testing). The Lambda functions will, respectively, create and delete the CF
stack. Yes--it's really that simple.

## Run Terraform

You will need an SSH Key Pair in EC2 because it is required by the "Docker for AWS" CF template, so
it needs to pre-exist. If you do not have one, create it using the EC2 console and remember its name for the
next step.

To create all the above in your AWS account, fetch the Terraform template and its dependencies from my
public GitHub repository: https://github.com/pknell/cloud-formation-daily-test

Open a shell into that directory, and run "terraform apply". You will be prompted to enter the name of your
SSH Key Pair.

This command will create a terraform.tfstate file in the current directory. This file is used by Terraform to remember
the identifiers of created resources.

You can now login to the AWS console to view the resources that Terraform created:
1. Go to CloudWatch, then Rules (under the Events sub-menu), and you'll see both the Start and Stop rules.
1. Go to Lambda, and you'll see both the Start and Stop Lambda functions.
1. At 9:30 AM CDT (or 14:30 UTC) the next day, you can go to CloudFormation to view the stack. Then, 30 minutes later,
you can view the stack being deleted.

## Terraform Walk-Through
The Terraform template file is called [start-stop-environment.tf](https://github.com/pknell/cloud-formation-daily-test/blob/master/start-stop-environment.tf).
This file starts with a provider:
```
provider "aws" {
  region = "us-west-2"
}
```
This provider configuration provides the region, which is required when using Terraform with AWS. If omitted, Terraform will prompt you to enter the region.

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
by means of the "manage_environment_iam_policy_attachment". The policy is separated in a json file that follows the
AWS policy JSON format. The policy I'm using includes all the permissions needed for the Docker CF template but
intentionally excludes items such as Billing, KMS, and deletion of CloudTrail logs. You'll need to create a policy 
(or customize this one) to meet the needs of your application stack and organization's requirements.

With the IAM role available, we can move on to creation of the Lambda functions:
```
resource "aws_lambda_function" "start_environment_lambda" {
  filename         = "start_env_lambda/start_environment_lambda_payload.zip"
  function_name    = "StartEnvironment"
  role             = "${aws_iam_role.manage_environment_iam_role.arn}"
  handler          = "index.handler"
  source_code_hash = "${base64sha256(file("start_env_lambda/start_environment_lambda_payload.zip"))}"
  runtime          = "nodejs8.10"
  memory_size      = 128
  timeout          = 15
}

resource "aws_lambda_function" "stop_environment_lambda" {
  filename         = "stop_env_lambda/stop_environment_lambda_payload.zip"
  function_name    = "StopEnvironment"
  role             = "${aws_iam_role.manage_environment_iam_role.arn}"
  handler          = "index.handler"
  source_code_hash = "${base64sha256(file("stop_env_lambda/stop_environment_lambda_payload.zip"))}"
  runtime          = "nodejs8.10"
  memory_size      = 128
  timeout          = 15
}
```

Here we create each Lambda function by referencing both the IAM role as well as the Lambda function's code. The
file format for the code varies depending on the language. For this example, since I used NodeJS, the format is a zip
file that contains at least one ".js" file.  The Lambda service will extract the contents of the zip and run the
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

Here you can see the cron expressions that define when each rule is triggered, as well as each "target" that specifies which Lambda function is called and the parameters (as JSON) to pass into the function.  Notice that the "input" for "start_environment_rule_target" includes the "ssh_key_name" variable--so that the nodes of the Docker Swarm cluster will allow for SSH access only by the specified key.

The last task is to set-up email notification so that someone will be notified whenever the CF stack creation
or deletion is unsuccessful. The process for doing this is somewhat tedious with the current version of CloudFormation,
but AWS has [documented it here](https://aws.amazon.com/premiumsupport/knowledge-center/cloudformation-rollback-email/).

## Clean-up
You can delete all the resources that Terraform created by returning to the shell in your "cloud-formation-daily-test"
directory and running the command "terraform destroy". If you want to leave the resources in place, but disable the
daily test, you can simply disable both CloudWatch rules. You can do this in the AWS console, or you can edit both
of the aws_cloudwatch_event_rule resources in start-stop-environment.tf so that they contain "enabled = false", and 
then run "terraform apply".

## Conclusion
Although there are a number of components involved (i.e., IAM, CloudWatch, Lambda, CloudFormation), the solution for
automating the testing of a CloudFormation Stack is fairly straight-forward. With the help of an additional Terraform
(or CloudFormation) template, it becomes so easy to set-up that there's little reason not to.
In the spirit of continuous testing and cost savings, enjoy!