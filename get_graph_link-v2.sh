if [ $# = 1 ];then
   num=$1
else 
   num=5
fi

ls -rt $(find ./blogGraph/ -type f) > re
s="![](https://raw.githubusercontent.com/yiwenshao/yiwenshao.github.io/graph/"
links=`cat re|while read line;do echo $s${line:2}")";done;`
link_array=($links)
total=${#link_array[@]}
echo $total
for((i=1;i<=$num;i++));do
    echo ${link_array[$total - $i]}
done
rm re
