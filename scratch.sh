#!/usr/bin/env sh

echo ok | awk '{print $1}'
echo ok | awk '{system("echo " $1)}'
