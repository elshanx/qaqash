#!/bin/sh
curl -s --max-time 600 -X POST --data-binary @- http://127.0.0.1:47831/event || exit 0
