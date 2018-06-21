variable "error_sms_phone_number" {
  type = "string"
}

resource "aws_sns_topic" "cloudformation-events" {
  name = "cloudformation-events"
  lambda_failure_feedback_role_arn = "${aws_iam_role.sns-cloudwatch-feedback-role.arn}"
}

resource "aws_sns_topic" "error-notification" {
  name = "error-notification"
}

resource "aws_sns_topic_subscription" "error-notification-sms-subscription" {
  topic_arn = "${aws_sns_topic.error-notification.arn}"
  protocol  = "sms"
  endpoint  = "${var.error_sms_phone_number}"
}

resource "aws_iam_policy" "allow-publish-to-sns-cloudformation-events" {
  name = "AllowLambdaPublishToSnsCloudformationEvents"
  policy = <<EOF
{   "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish",
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "${aws_sns_topic.cloudformation-events.arn}"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_policy" "allow-publish-to-sns-error-notification" {
  name = "AllowLambdaPublishToSns"
  policy = <<EOF
{   "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": [
                "${aws_sns_topic.error-notification.arn}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
EOF
}

resource "aws_iam_role" "error_notification_iam_role" {
  name = "ErrorNotificationRole"
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

resource "aws_iam_policy_attachment" "error_notification_iam_policy_attachment" {
    name = "ErrorNotificationPolicyAttachment"
    policy_arn = "${aws_iam_policy.allow-publish-to-sns-error-notification.arn}"
    roles = ["${aws_iam_role.error_notification_iam_role.name}"]
}

resource "aws_iam_policy_attachment" "cloudformation_events_iam_policy_attachment" {
    name = "CloudformationEventsPolicyAttachment"
    policy_arn = "${aws_iam_policy.allow-publish-to-sns-cloudformation-events.arn}"
    roles = ["${aws_iam_role.manage_environment_iam_role.name}"]
}

resource "aws_iam_policy" "allow-cloudwatch-write" {
  name = "AllowCloudwatchWrite"
  policy = <<EOF
{   "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
EOF
}

resource "aws_iam_role" "sns-cloudwatch-feedback-role" {
  name = "SnsCloudwatchFeedbackRole"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "sns.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy_attachment" "sns_cloudwatch_feedback_iam_policy_attachment" {
    name = "SnsCloudwatchFeedbackPolicyAttachment"
    policy_arn = "${aws_iam_policy.allow-cloudwatch-write.arn}"
    roles = ["${aws_iam_role.sns-cloudwatch-feedback-role.name}"]
}

data "archive_file" "error_notify_lambda_zip" {
    type        = "zip"
    source_dir  = "error_notify_lambda"
    output_path = "lambda-packages/error_notify_lambda_payload.zip"
}

resource "aws_lambda_function" "error_notify_lambda" {
  filename         = "lambda-packages/error_notify_lambda_payload.zip"
  function_name    = "ErrorNotify"
  role             = "${aws_iam_role.error_notification_iam_role.arn}"
  handler          = "index.handler"
  source_code_hash = "${data.archive_file.error_notify_lambda_zip.output_base64sha256}"
  runtime          = "nodejs8.10"
  memory_size      = 128
  timeout          = 15
}

resource "aws_lambda_permission" "allow_sns_error_notify" {
  statement_id   = "AllowExecutionFromSns"
  action         = "lambda:InvokeFunction"
  function_name  = "${aws_lambda_function.error_notify_lambda.function_name}"
  principal      = "sns.amazonaws.com"
  source_arn     = "${aws_sns_topic.cloudformation-events.arn}"
}

resource "aws_sns_topic_subscription" "cloudformation_events_lambda_subscription" {
  topic_arn = "${aws_sns_topic.cloudformation-events.arn}"
  protocol  = "lambda"
  endpoint  = "${aws_lambda_function.error_notify_lambda.arn}"
}

