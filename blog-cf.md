# AWS CloudFormation Daily Testing
*© 2018 Paul Knell, NVISIA LLC*

When it comes to Amazon Web Services (AWS), infrastructure scripting is typically done using either
[CloudFormation (CF)](https://aws.amazon.com/cloudformation), which is an AWS service,
or [Terraform](https://www.terraform.io/) (an open-source tool). These tools allow you to represent all the
resources in your cloud environment using template files, thereby allowing
you to easily create additional similar environments for purposes such as development, testing, and 
quality assurance. These test environments are not necessarily always needed--sometimes they're
only needed during daytime hours, or sometimes only during certain project phases. Using the template files to remove/restore
 your environment is not the only way to cut nightly costs--there's also [scheduled autoscaling groups](https://docs.aws.amazon.com/autoscaling/ec2/userguide/schedule_time.html), and an [instance scheduler tool](https://aws.amazon.com/answers/infrastructure-management/instance-scheduler/).
 However, maintaining the templates is unquestionably useful for testing infrastructure changes without much risk of impacting your other environments.
How will you know that the template you wrote and used today will still work when you need it again months from now?
A simple daily test should give you that confidence and notify you if anything breaks.
 So, how can we set up daily CF stack creation and removal? Answer: Lambda + CloudWatch Rules. This article works through 
 a template that sets up this kind of daily test.

For the sake of having an example CF stack, we are using the [Docker for AWS Community Edition](https://docs.docker.com/docker-for-aws/#quickstart)
as the CF template that's being tested, but the idea is that you would use your own project's template instead.

The image below depicts the entire setup, and we'll walk through how to run and understand the template
that sets everything up. All you will need is an AWS account. 

![Overview Diagram](https://github.com/pknell/cloud-formation-daily-test/blob/master/diagram.png)

The test works as follows: CloudWatch Rules are used to trigger Lambda functions based on cron expressions, which you 
can tweak to adjust the start/stop times. The Lambda functions will, respectively, create and delete the CF stack.

You can set up this test in your own AWS account by using [this CF template](https://github.com/pknell/cloud-formation-daily-test/blob/master/start-stop-environment-cf.yaml).
The remainder of this article (after account creation) works through understanding this template.

This is part 1 of a 2-part series. In the [second article](https://github.com/pknell/cloud-formation-daily-test/blob/master/blog-tf.md), I re-write this article's CloudFormation template using Terraform,
and then compare the two technologies.

## Create an AWS Account

*Skip this step if you already have an account.* Go to https://aws.amazon.com and
select "Create AWS Account" at the upper-right corner (alternatively, click the "Sign In to the Console" button and then 
"Create a new AWS account"). You then work through entering your information, legal agreements, and identity verification.

## Create the CF Stack

You will need an SSH Key Pair in EC2 because it is required by the "Docker for AWS" CF template that this example is
using. If you do not have one, [create it using the EC2 console](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#having-ec2-create-your-key-pair) and remember its name for the
next step.

Log into the [AWS Console](https://console.aws.amazon.com), and select "CloudFormation" from the Services menu. Select
"Create a new stack". For the template selection, download the [template file](https://raw.githubusercontent.com/pknell/cloud-formation-daily-test/master/start-stop-environment-cf.yaml) and then upload it using "Upload a template to Amazon S3"

![Upload Template](https://github.com/pknell/cloud-formation-daily-test/blob/master/cf-images/upload-template.png)

Click "Next" and then enter a stack name and the name of your SSH key pair.

![Stack Details](https://github.com/pknell/cloud-formation-daily-test/blob/master/cf-images/stack-details.png)

Click "Next", then "Next" again (to use the default options), enable the checkbox for IAM resource capabilities, and then "Create".

![IAM Acknowledge](https://github.com/pknell/cloud-formation-daily-test/blob/master/cf-images/iam-acknowledge.png)

Wait until the status changes to "Create Complete".
 
You can now use the AWS console to view the created resources:
1. Go to CloudWatch, then Rules (under the Events sub-menu), and you'll see both the Start and Stop rules.
![Rules](https://github.com/pknell/cloud-formation-daily-test/blob/master/cf-images/rules.png)
1. Go to Lambda, and you'll see both the Start and Stop Lambda functions.
![Lambda](https://github.com/pknell/cloud-formation-daily-test/blob/master/cf-images/lambda.png)
1. At 9:30 AM CDT (or 14:30 UTC) the next day, you can go to CloudFormation to view the stack. Then, 30 minutes later,
you can view the stack being deleted. You can tweak the cron expressions of the rules to adjust these times.
You can find information on the cron format in the [CloudWatch Scheduled Events documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html#CronExpressions).
1. After the Lambda function(s) have executed, you can go to [Logs in the CloudWatch console](https://console.aws.amazon.com/cloudwatch/home#logs:)
to view logs created by Lambda.
1. Since this example runs the Docker template: While the CloudFormation stack is up, you can use your SSH key to connect
an SSH client to the running EC2 instances that are part of the [Docker Swarm](https://docs.docker.com/engine/swarm/key-concepts/).

## Template Walk-Through
The template file ([start-stop-environment-cf.yaml](https://github.com/pknell/cloud-formation-daily-test/blob/master/start-stop-environment-cf.yaml))
starts with a "Metadata" section. This section is used by the [CloudFormation Designer tool](http://console.aws.amazon.com/cloudformation/designer),
to store diagram coordinates. If you open the template file in the Designer, you can view it graphically:

![Template Design Diagram](https://github.com/pknell/cloud-formation-daily-test/blob/master/cf-images/template-design.png)

The next section is "Parameters". This section is for any user input; in this example, it's just the name of the SSH key.
```
Parameters:
  SshKeyNameParameter:
    Type: String
    Default: Your-SSH-Key-Name
    Description: The EC2 keypair name for instance SSH access.
```

If the template that you're testing has different parameters, you'll either specify them as I did for SSH key name or
you could hard-code them in the lambda function.

The next section is "Resources", which declares each resource depicted in the design diagram (above).
It starts with an IAM policy and role used by the Lambda functions so that they have the necessary permissions to 
create and delete the CF stack:

```
  ManageEnvironmentIamPolicy:
    Type: 'AWS::IAM::Policy'
    Properties:
      PolicyName: ManageEnvPolicy
      Roles:
        - Ref: ManageEnvRole
      PolicyDocument:
        Version: 2012-10-17
        Statement:
          - Effect: Allow
            Action:
              - 'logs:CreateLogGroup'
              - 'logs:CreateLogStream'
              - 'logs:DeleteLogGroup'
              - 'logs:DeleteLogStream'
              ...etc
```

```
  ManageEnvRole:
    Type: 'AWS::IAM::Role'
    Properties:
      RoleName: ManageEnvRole
      AssumeRolePolicyDocument:
        Version: 2012-10-17
        Statement:
          - Action: 'sts:AssumeRole'
            Principal:
              Service:
                - lambda.amazonaws.com
            Effect: Allow
            Sid: ''
```

The policy I'm using includes all the permissions needed for the Docker CF template but
intentionally excludes items such as Billing, KMS, and deletion of CloudTrail logs. If you're testing your project's
CF template, you'll need to create a policy (or customize this one) to meet the needs of your application stack and 
organization's requirements.

After IAM, the next resources are the Lambda functions:
```
  StartEnvironment:
    Type: 'AWS::Lambda::Function'
    Properties:
      Handler: index.handler
      MemorySize: 128
      Timeout: 15
      Role:
        'Fn::GetAtt':
          - ManageEnvRole
          - Arn
      Runtime: nodejs6.10
      Code:
        ZipFile: |
          exports.handler = function(event, context, callback) {
             ...code is listed here
          }
          
  StopEnvironment:
    Type: 'AWS::Lambda::Function'
    Properties:
      Handler: index.handler
      MemorySize: 128
      Timeout: 15
      Role:
        'Fn::GetAtt':
          - ManageEnvRole
          - Arn
      Runtime: nodejs6.10
      Code:
        ZipFile: |
          exports.handler = function(event, context, callback) {
             ...code is listed here
          }
```

Here we create each Lambda function by referencing both the IAM role as well as the Lambda function's code. With
CloudFormation, there are two ways of including the code--either embedded in the template with a ZipFile element, or
placed into S3 and referenced [with S3Bucket, S3Key, and S3ObjectVersion](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-lambda-function-code.html).

Here's the code listing for StartEnvironment:
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
parameters (as opposed to parameters of the createStack call). When you're testing with your own project (rather than Docker.templ),
you'll probably have different parameters because 'KeyName', 'ManagerSize', and 'ClusterSize' are specific to the Docker template.
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
creation/deletion, there are resources for the CloudWatch Rules that will trigger those functions on a schedule:
```
  StartRule:
    Type: 'AWS::Events::Rule'
    Properties:
      Name: StartEnvironmentRule
      ScheduleExpression: cron(30 14 ? * 2-6 *)
      Targets:
        - Arn: !GetAtt
            - StartEnvironment
            - Arn
          Id: start_environment_rule_target
          Input: !Join
            - ''
            - -  '{ "stackName": "MyStack", "keyPairName": "'
              - Ref: SshKeyNameParameter
              - '" }'
              
  StopRule:
    Type: 'AWS::Events::Rule'
    Properties:
      Name: StopEnvironmentRule
      ScheduleExpression: cron(0 15 ? * 2-6 *)
      Targets:
        - Arn: !GetAtt
            - StopEnvironment
            - Arn
          Id: stop_environment_rule_target
          Input: '{ "stackName": "MyStack" }'
```

Here you can see the cron expressions that define when each rule is triggered, as well as each "target" that specifies 
which Lambda function is called and the parameters (as JSON) to pass into the function.  Notice that the "Input" for 
"StartRule" includes the "SshKeyName" parameter--so that the nodes of the Docker Swarm cluster will allow SSH access 
only by the specified key.

After creating the rules, we need to authorize them to call the Lambda functions:
```
  AllowCloudwatchStartEnv:
    Type: 'AWS::Lambda::Permission'
    Properties:
      Action: 'lambda:InvokeFunction'
      FunctionName: !GetAtt
        - StartEnvironment
        - Arn
      Principal: events.amazonaws.com
      SourceArn: !GetAtt
        - StartRule
        - Arn
        
  AllowCloudwatchStopEnv:
    Type: 'AWS::Lambda::Permission'
    Properties:
      Action: 'lambda:InvokeFunction'
      FunctionName: !GetAtt
        - StopEnvironment
        - Arn
      Principal: events.amazonaws.com
      SourceArn: !GetAtt
        - StopRule
        - Arn
```

The creation of these Lambda permissions is done for you automatically when you're using the AWS console to create the
rules, but with CloudFormation it needs to be done explicitly. The FunctionName can be the ARN of a specific [version](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-lambda-version.html)
or [alias](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-lambda-alias.html) of the Lambda function.

The last task is to set-up email (or SMS) notification so that someone will be notified whenever the CF stack creation
or deletion is unsuccessful. The process for doing this is somewhat tedious, but AWS has [documented it here](https://aws.amazon.com/premiumsupport/knowledge-center/cloudformation-rollback-email/).
You can refer to [the "error-notify-using-sms" branch](https://github.com/pknell/cloud-formation-daily-test/tree/error-notify-using-sms)
of my GitHub project for an example. Essentially, it entails:
 1. Additional template parameter for email address (or SMS phone number)
 1. Addition of: IAM policies and roles and SNS topics
 1. Addition of NotificationARNs parameter during stack creation, and Lambda function for SNS publish if stack creation rolls-back due to failure
 1. Revision of the StartEnvironment lambda function to write to the SNS topic if an error is received

## Clean-up
When you're done, you can remove the stack via the CloudFormation console:

![Delete Stack](https://github.com/pknell/cloud-formation-daily-test/blob/master/cf-images/delete-stack.png)

If the environment is started and not stopped (e.i., the stack called "MyStack" exists), then remove that stack as well.

## Conclusion
Although there are a number of services involved (i.e., IAM, CloudWatch, Lambda, CloudFormation), the solution for
automating a daily test of a CloudFormation Stack is fairly simple. The addition of email or SMS notification adds a
number of additional components, but it is still practical and easily understood.
