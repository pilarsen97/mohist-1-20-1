#!/bin/sh
cd "$(dirname "$(readlink -fn "$0")")"
java -Xms1G -Xmx2G -jar mohist-1.20.1-2eb79df.jar