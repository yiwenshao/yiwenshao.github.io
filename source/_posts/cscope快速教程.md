---
title: cscope快速教程
date: 2016-12-25 21:15:20
tags: cscope
categories: 工具使用
---

cscope是一种代码阅读工具, 跟ctags比, 优点是可以查询调用某个函数的有哪些函数. 本文基于参考文献, 整理其基本使用方法, 方便快速查询,  本文测试环境是Ubuntu16.04.

<!--more-->
#### 以Redis代码为例子

我们以Redis的源码为例子, 首先在[Reids官网](https://redis.io/)下载源码, 并且解压, 进入代码目录. 开始进入以下步骤:

+ 将源码文件名写入到cscope.files文件中

```
find . -name "*.c" -o -name "*.cpp" -o -name "*.h" -o -name "*.hpp" > cscope.files
```
由于find命令会递归查找所有子目录的文件, 我们通过这一步可以获得所有需要的文件名. 

+ 建立数据库

```
cscope -R -b -i cscope.files

-q表示速度快,
-R递归
-b表示只建立数据库, 但是不进入交互操作界面
```

+ 进入交互界面开始操作

```
cscope -d 
```
通过上面的命令, 可以进入交互的界面, 其实例如下:

```
Find this C symbol:
Find this global definition:
Find functions called by this function:
Find functions calling this function:
Find this text string:
Change this text string:
Find this egrep pattern:
Find this file:
Find files #including this file:
Find assignments to this symbol:
```
我们可以输入字符, 敲回车, 进行上面列出来的基本的查询操作.


+ ctrl + d 可以退出交互界面, 结束查询.


#### 查询操作实例

有了上面的流程以后, 基本的查询没有问题了, 我们在此给出一些操作的实例.

##### 交互查询

+ 查询main函数

```
Find this C symbol: main
```
在对应的行输入main, 然后选择和是的选项回车进入对应的文件.

+ 查询调用aeCreateTimeEvent函数的位置

```
Find functions calling this function: aeCreateTimeEvent
```
在上面所述的位置敲回车, 可以查到如下的结果. 

```
  File              Function   Line
0 redis-benchmark.c main        663 aeCreateTimeEvent(config.el,1,showThroughput,NULL,NULL);
1 server.c          initServer 1955 if(aeCreateTimeEvent(server.el, 1, serverCron, NULL, NULL) == AE_ERR) {
```
这是ctags做不到的查询. 其他的基于文件名的查询, 或者基于字符匹配的查询可以自行尝试. 


##### 命令行查询

cscope也支持命令行查询. 首先配置CSCOPE_DB:

```
//根据具体路径调整配置
export CSCOPE_DB= /home/casualet/redis-3.2.6/cscope.out
```

然后用vim进入文件./src/server.c, 然后进行如下的配置:

```
:cs add $CSCOPE_DB
```
这样就可以开始使用命令进行代码阅读了. 举例来说:

+ 查询有哪些函数调用了initServer函数
```
:cs find c initServer
```
可以查到main函数中调用这个函数的位置. 

+ 查询initServer定义的位置

```
:cs find g initServer
```
通过上面的命令就可以找到initServer函数的定义位置. 

+ 查找initServer出现的所有位置
```
:cs find g initServer
```
另外, 如果把上面的cs命令改成scs或者vert scs, 则支持查找结果另开一个小窗口.  这样, 最常用的三个功能就可以用了. 其他功能列表如下:

|命令参数|对应功能|
|-|-|
|c| Find functions calling this function|
|d| Find functions called by this function|
|e| Find this egrep pattern|
|f| Find this file|
|g| Find this definition|
|i| Find files #including this file|
|s| Find this C symbol|
|t| Find this text string|
|help | Show this message (Usage: help)|
|kill | Kill a connection (Usage: kill #)|
|reset| Reinit all connections (Usage: reset)|
|show | Show connections (Usage: show)|

##### 设置快捷键

可以点击参考文献的做法, 设置了快捷键以后, 更加方便了. 



#### 相关文献

[[1] http://www.cnblogs.com/sunj/archive/2012/03/12/2391610.html](http://www.cnblogs.com/sunj/archive/2012/03/12/2391610.html)
[[2] https://courses.cs.washington.edu/courses/cse451/12sp/tutorials/tutorial_cscope.html](https://courses.cs.washington.edu/courses/cse451/12sp/tutorials/tutorial_cscope.html)
[[3] http://cscope.sourceforge.net/](http://cscope.sourceforge.net/)
[[4] 关于shortcut](http://cscope.sourceforge.net/cscope_maps.vim)
[[5] http://cscope.sourceforge.net/cscope_vim_tutorial.html](http://cscope.sourceforge.net/cscope_vim_tutorial.html)
[[6] https://a0gustinus.wordpress.com/2013/06/01browsing-source-code-in-linux-vimcscope/](https://a0gustinus.wordpress.com/2013/06/01browsing-source-code-in-linux-vimcscope/)
