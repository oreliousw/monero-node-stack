#!/usr/bin/env python3
"""
send_sns.py - simple SNS notifier for monero-node-stack

Usage:
  python3 send_sns.py "Subject" "Message body"
"""

import os
import sys
import boto3

def main():
    if len(sys.argv) < 3:
        print("Usage: send_sns.py <subject> <message>", file=sys.stderr)
        sys.exit(1)

    subject = sys.argv[1]
    message = sys.argv[2]

    topic_arn = os.environ.get("MONERO_SNS_ARN") or "arn:aws:sns:us-west-2:381328847089:monero-alerts"
    region = topic_arn.split(":")[3] if ":" in topic_arn else "us-west-2"

    sns = boto3.client("sns", region_name=region)
    sns.publish(TopicArn=topic_arn, Subject=subject[:100], Message=message)

if __name__ == "__main__":
    main()
