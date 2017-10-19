ls -rt $(find ./blogGraph/ -type f) > re

s="![](https://yiwenshao.github.io/"

cat re|while read line;do echo $s${line:2}")"; done;

rm re
