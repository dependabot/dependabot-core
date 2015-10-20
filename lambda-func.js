var aws = require('aws-sdk');
var sqs = new aws.SQS({region:'eu-west-1'});

exports.handler = function() {
    var msg = {
        "repo": {
            "language": "ruby",
            "name": "gocardless/bump-test"
        }
    };

    var sqsParams = {
        MessageBody: JSON.stringify(msg),
        QueueUrl: 'https://sqs.eu-west-1.amazonaws.com/442311777686/bump-repos_to_fetch_files_for'
    };

    sqs.sendMessage(sqsParams, function(err, data) {
        if (err) {
            console.log('ERR', err);
        }

        console.log(data);
    });
}
