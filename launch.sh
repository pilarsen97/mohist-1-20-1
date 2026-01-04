#!/bin/sh
cd "$(dirname "$(readlink -fn "$0")")"
java -Xms4G -Xmx6G -Xss256k -jar mohist-1.20.1-2eb79df.jar nogui