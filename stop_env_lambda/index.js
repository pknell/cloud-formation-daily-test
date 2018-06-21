exports.handler = function(event, context, callback) {

   var AWS = require('aws-sdk');
   var cloudformation = new AWS.CloudFormation();

    var params = {
      StackName: event.stackName /* required */
      /*,RetainResources: [
        'STRING_VALUE'
      ]*/
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
