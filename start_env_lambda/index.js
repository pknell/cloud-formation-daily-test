exports.handler = function(event, context, callback) {

   var AWS = require('aws-sdk');
   var cloudformation = new AWS.CloudFormation();

   var account_id = context.invokedFunctionArn.split(":")[4]
   var region = process.env.AWS_DEFAULT_REGION

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
     TimeoutInMinutes: 20,
     NotificationARNs: [ 'arn:aws:sns:' + region + ':' + account_id + ':cloudformation-events' ]
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
