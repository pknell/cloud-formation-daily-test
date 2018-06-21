AWS = require('aws-sdk'); 

exports.handler = function(event, context) {
    const message = event.Records[0].Sns.Message;
    if (message.indexOf("ROLLBACK_IN_PROGRESS") > -1) {
        var fields = message.split("\n");
        var subject = fields[11].replace(/['']+/g, '');
        var account_id = context.invokedFunctionArn.split(":")[4]
        var region = process.env.AWS_DEFAULT_REGION
        var topic_arn = "arn:aws:sns:" + region + ":" + account_id + ":error-notification"
        send_SNS_notification(subject, message, topic_arn);   
    }
};

function send_SNS_notification(subject, message, topic_arn) {
    var sns = new AWS.SNS();
    subject = subject + " is in ROLLBACK_IN_PROGRESS";
    sns.publish({ 
        Subject: subject,
        Message: message,
        TopicArn: topic_arn
    }, function(err, data) {
        if (err) {
            console.log(err.stack);
            return;
        } 
        console.log('push sent');
        console.log(data);
    });
}
