#!/bin/bash
echo "This is a output for command error command."

# Simulate an error output to stderr
echo "This is an error message." >&2

# Simulate a hang
sleep 30