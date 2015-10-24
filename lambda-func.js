var aws = require('aws-sdk');
var sqs = new aws.SQS({region:'eu-west-1'});

exports.handler = function(event, context) {
    var repos = [
        { language: 'ruby', name: 'gocardless/payments-service' },
        { language: 'ruby', name: 'gocardless/gocardless' },
        { language: 'ruby', name: 'gocardless/auth-service' },
        { language: 'ruby', name: 'gocardless/dashboard' }
    ];

    var messagesSent = 0;
    repos.forEach(function(repo) {
        var sqsParams = {
            MessageBody: JSON.stringify({ repo: repo }),
            QueueUrl: 'https://sqs.eu-west-1.amazonaws.com/442311777686/bump-repos_to_fetch_files_for'
        };
        sqs.sendMessage(sqsParams, function(err, data) {
            if (err) {
                console.log('ERR', err);
            }
            console.log(data);

            messagesSent += 1;
            if (messagesSent == repos.length) {
                context.done();
            }
        });
    });
}
